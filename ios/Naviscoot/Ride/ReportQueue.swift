import Foundation

struct PendingReport: Codable, Equatable, Identifiable {
    let id: UUID
    let lat: Double
    let lon: Double
    let time: Date
    let routeId: String?
}

enum ReportSendError: Error, Equatable {
    case rejected(status: Int)
    case retryable
}

protocol ReportSending {
    func send(_ report: PendingReport) async throws
}

enum ReportOutcome: Equatable {
    case sent
    case queued
    case rejected
}

@MainActor
final class ReportQueue: ObservableObject {
    @Published private(set) var pending: [PendingReport]
    private let sender: ReportSending?
    private let storeURL: URL?
    private let retryDelays: [TimeInterval]
    private var failures = 0
    private var retryTask: Task<Void, Never>?
    private var flushing = false
    private var rejectedIDs: Set<UUID> = []

    init(sender: ReportSending?, storeURL: URL?, retryDelays: [TimeInterval] = [10, 30, 60, 120, 300]) {
        self.sender = sender
        self.storeURL = storeURL
        self.retryDelays = retryDelays
        pending = storeURL.flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? Self.decoder.decode([PendingReport].self, from: $0) } ?? []
    }

    static var defaultStoreURL: URL? {
        try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "pending-reports.json")
    }

    func submit(_ report: PendingReport) async -> ReportOutcome {
        pending.append(report)
        persist()
        await flush()
        if pending.contains(where: { $0.id == report.id }) {
            return .queued
        }
        return rejectedIDs.contains(report.id) ? .rejected : .sent
    }

    func flush() async {
        guard let sender, !flushing else { return }
        flushing = true
        defer { flushing = false }
        while let next = pending.first {
            do {
                try await sender.send(next)
            } catch ReportSendError.rejected {
                rejectedIDs.insert(next.id)
            } catch {
                failures += 1
                scheduleRetry()
                return
            }
            pending.removeFirst()
            persist()
        }
        failures = 0
        retryTask?.cancel()
        retryTask = nil
    }

    private func scheduleRetry() {
        guard !retryDelays.isEmpty else { return }
        let delay = retryDelays[min(failures, retryDelays.count) - 1]
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.flush()
        }
    }

    private func persist() {
        guard let storeURL, let data = try? Self.encoder.encode(pending) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
