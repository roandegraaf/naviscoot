import Foundation
import Observation
import Security

struct ScooterKeychain {
    enum Item: String {
        case password
        case ident
    }

    private let service: String

    init(service: String = "nl.naviscoot.scooter") {
        self.service = service
    }

    func value(_ item: Item) -> [UInt8]? {
        var query = query(item)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return Array(data)
    }

    // AfterFirstUnlock so a ride can still talk to the scooter while the phone is locked.
    @discardableResult
    func save(_ bytes: [UInt8], as item: Item) -> Bool {
        SecItemDelete(query(item) as CFDictionary)
        var entry = query(item)
        entry[kSecValueData as String] = Data(bytes)
        entry[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(entry as CFDictionary, nil) == errSecSuccess
    }

    func remove(_ item: Item) {
        SecItemDelete(query(item) as CFDictionary)
    }

    private func query(_ item: Item) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: item.rawValue]
    }
}

enum ScooterPrefill {
    static func apply(info: [String: Any]?, settings: AppSettings, keychain: ScooterKeychain) {
        if settings.scooterSerial.isEmpty, let serial = text("NaviscootScooterSerial", in: info) {
            settings.scooterSerial = serial
        }
        seed(.password, from: "NaviscootScooterPassword", in: info, keychain: keychain)
        seed(.ident, from: "NaviscootScooterIdent", in: info, keychain: keychain)
    }

    private static func seed(_ item: ScooterKeychain.Item, from key: String, in info: [String: Any]?, keychain: ScooterKeychain) {
        guard keychain.value(item) == nil, let bytes = text(key, in: info).flatMap(ScooterPassword.parse) else { return }
        keychain.save(bytes, as: item)
    }

    private static func text(_ key: String, in info: [String: Any]?) -> String? {
        guard let value = (info?[key] as? String)?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
        return value
    }
}

@MainActor
@Observable
final class ScooterConnection {
    enum State: Equatable {
        case off
        case connecting
        case connected
        case failed(ScooterError)
    }

    static let shared = ScooterConnection(settings: .shared, keychain: ScooterKeychain())

    private(set) var state: State = .off
    private(set) var telemetry: ScooterTelemetry?
    private(set) var telemetryAt: Date?
    private(set) var clockSync: TimeZoneSync?
    var rideActive = false
    @ObservationIgnored var onLinkLost: ((Date) -> Void)?
    @ObservationIgnored var onTelemetry: ((ScooterTelemetry) -> Void)?

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let keychain: ScooterKeychain
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var session: NinebotSession?
    @ObservationIgnored private var link: ScooterBluetoothLink?
    @ObservationIgnored private var queueTail: Task<Void, Never>?
    @ObservationIgnored private let pollInterval: Duration

    #if DEBUG
    @ObservationIgnored private let simulation: ScooterSimulation?

    init(settings: AppSettings, keychain: ScooterKeychain, pollInterval: Duration = .seconds(5), simulation: ScooterSimulation? = .requested()) {
        self.settings = settings
        self.keychain = keychain
        self.pollInterval = pollInterval
        self.simulation = simulation
    }
    #else
    init(settings: AppSettings, keychain: ScooterKeychain, pollInterval: Duration = .seconds(5)) {
        self.settings = settings
        self.keychain = keychain
        self.pollInterval = pollInterval
    }
    #endif

    var isConfigured: Bool {
        #if DEBUG
        if simulation != nil { return true }
        #endif
        return !settings.scooterSerial.isEmpty && keychain.value(.password) != nil
    }

    // Only started once a scooter is configured, so a fresh install never sees the Bluetooth permission prompt.
    func start() {
        guard loop == nil, isConfigured else { return }
        #if DEBUG
        if let simulation {
            loop = Task { [weak self] in await self?.runSimulated(simulation) }
            return
        }
        #endif
        loop = Task { [weak self] in await self?.run() }
    }

    #if DEBUG
    private func runSimulated(_ simulation: ScooterSimulation) async {
        state = .connecting
        let session = NinebotSession(transport: simulation.makeScooter(), serial: ScooterSimulation.serial, password: ScooterSimulation.password, listenWindow: .zero)
        do {
            try await session.authenticate()
            self.session = session
            state = .connected
            if !rideActive { clockSync = try? await run { try await ScooterClock.sync(session: $0) } }
            try await poll()
        } catch {
            guard !Task.isCancelled else { return }
            self.session = nil
            state = .failed(error as? ScooterError ?? .unexpectedResponse)
        }
    }
    #endif

    func stop() {
        loop?.cancel()
        loop = nil
        link?.disconnect()
        link = nil
        session = nil
        state = .off
    }

    func restart() {
        stop()
        start()
    }

    // Every request goes through here one at a time: replies share one inbox, so interleaved requests would steal each other's answers.
    func run<T>(_ body: @escaping (NinebotSession) async throws -> T) async throws -> T {
        let previous = queueTail
        let task = Task { @MainActor [weak self] () async throws -> T in
            await previous?.value
            guard let session = self?.session else { throw ScooterError.disconnected }
            return try await body(session)
        }
        queueTail = Task { _ = try? await task.value }
        return try await task.value
    }

    private func run() async {
        var backoff: Duration = .seconds(2)
        while !Task.isCancelled {
            guard let password = keychain.value(.password) else {
                state = .off
                return
            }
            let serial = settings.scooterSerial
            let link = ScooterBluetoothLink(serial: serial, knownPeripheral: UUID(uuidString: settings.scooterPeripheralID))
            self.link = link
            state = .connecting
            do {
                try await link.connect()
                if let identifier = link.peripheralIdentifier { settings.scooterPeripheralID = identifier.uuidString }
                let session = NinebotSession(transport: link, serial: serial, password: password)
                try await session.authenticate()
                self.session = session
                state = .connected
                backoff = .seconds(2)
                if !rideActive { clockSync = try? await run { try await ScooterClock.sync(session: $0) } }
                try await poll()
            } catch let error as ScooterError {
                lose(link, error)
                if error == .passwordRejected || error == .serialRejected || error == .bluetoothDenied { return }
                if error == .heldByOtherApp {
                    try? await Task.sleep(for: .seconds(3))
                    continue
                }
            } catch {
                lose(link, .unexpectedResponse)
            }
            try? await Task.sleep(for: backoff)
            backoff = min(backoff * 2, .seconds(60))
        }
    }

    private func poll() async throws {
        var misses = 0
        while !Task.isCancelled {
            do {
                let fresh = try await run { try await $0.readTelemetry() }
                telemetry = fresh
                telemetryAt = Date()
                misses = 0
                onTelemetry?(fresh)
            } catch ScooterError.timeout {
                misses += 1
                if misses >= 3 { throw ScooterError.timeout }
            }
            try await Task.sleep(for: pollInterval)
        }
    }

    private func lose(_ link: ScooterBluetoothLink, _ error: ScooterError) {
        let wasConnected = state == .connected
        link.disconnect()
        session = nil
        self.link = nil
        state = .failed(error)
        if wasConnected { onLinkLost?(Date()) }
    }
}
