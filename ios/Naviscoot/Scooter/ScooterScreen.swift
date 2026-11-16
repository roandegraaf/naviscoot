import Observation
import SwiftUI

enum ScooterStatus {
    static func text(_ state: ScooterConnection.State, telemetry: ScooterTelemetry?) -> String {
        switch state {
        case .off: Strings.scooterStatusNotSetUp
        case .connecting: Strings.scooterStatusConnecting
        case .connected: telemetry.map { "\($0.batteryPercent)%" } ?? Strings.scooterStatusConnected
        case .failed: Strings.scooterStatusNotConnected
        }
    }
}

struct ScooterBatterySummary: Equatable {
    let health: String?
    let cycles: String?
    let temperature: String?
    let fullIn: String?

    init(report: BatteryReport?, timeToFullMinutes: Int?, language: Language = .current) {
        health = report?.healthPercent.map { Self.number("%.0f%%", $0, language: language) }
        cycles = report?.cycles.map(String.init)
        temperature = report.flatMap { Self.temperature($0.temperaturesC) }
        fullIn = Self.fullIn(minutes: timeToFullMinutes, charging: report?.isCharging, language: language)
    }

    static func fullIn(minutes: Int?, charging: Bool?, language: Language = .current) -> String? {
        guard let minutes, minutes > 0, charging != false else { return nil }
        return Strings.format("scooter.screen.fullIn", Format.duration(seconds: Double(minutes) * 60, language: language), language: language)
    }

    static func number(_ format: String, _ value: Double, language: Language = .current) -> String {
        String(format: format, locale: language.locale, value)
    }

    static func temperature(_ values: [Int]) -> String? {
        guard let low = values.min(), let high = values.max() else { return nil }
        return low == high ? "\(low) °C" : "\(low)–\(high) °C"
    }
}

@MainActor
@Observable
final class ScooterBatteryReadings {
    private(set) var report: BatteryReport?
    private(set) var timeToFullMinutes: Int?
    private(set) var charge = ChargeTracker()

    func keepFresh(_ scooter: ScooterConnection) async {
        while !Task.isCancelled {
            await refresh(scooter)
            try? await Task.sleep(for: .seconds(10))
        }
    }

    private func refresh(_ scooter: ScooterConnection) async {
        if let fresh = try? await scooter.run({ await BatteryReport.read(from: $0) }) {
            report = fresh
            if let percent = fresh.chargePercent { charge.record(percent, at: Date()) }
        }
        timeToFullMinutes = (try? await scooter.run { try? await $0.value(.timeToFull) }) ?? nil
    }
}

struct ScooterScreen: View {
    @Bindable var settings: AppSettings
    @Environment(ScooterConnection.self) private var scooter
    @State private var readings = ScooterBatteryReadings()
    @State private var hasPassword = false
    @State private var hasIdent = false
    @State private var canControl = false
    @State private var passwordInput = ""
    @State private var identInput = ""
    @State private var passwordInvalid = false
    @State private var identInvalid = false
    @State private var notifyDenied = false
    @State private var actionMessage: String?
    @State private var confirmingPowerOff = false
    @State private var busy = false
    private let keychain = ScooterKeychain()

    var body: some View {
        List {
            heroSection
            controlsSection
            batterySection
            notifySection
            rangeSection
            advancedSection
            connectionSection
            pairingSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Strings.scooterSection)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            hasPassword = keychain.value(.password) != nil
            hasIdent = keychain.value(.ident) != nil
            canControl = scooter.vehicleIdent != nil
        }
        .task(id: scooter.state == .connected) {
            guard scooter.state == .connected else { return }
            await readings.keepFresh(scooter)
        }
        .confirmationDialog(Strings.scooterPowerOffConfirm, isPresented: $confirmingPowerOff, titleVisibility: .visible) {
            Button(Strings.scooterPowerOff, role: .destructive) { perform(.powerOff) }
                .accessibilityIdentifier("settings.scooter.powerOff.confirm")
        }
    }

    private var glance: ScooterGlance? { ScooterGlance(scooter) }

    private var summary: ScooterBatterySummary {
        ScooterBatterySummary(report: readings.report, timeToFullMinutes: readings.timeToFullMinutes, language: settings.language)
    }

    private var heroSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: glance?.battery ?? "–")
                        .font(.system(size: 60, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink)
                        .accessibilityLabel(Strings.scooterBattery)
                        .accessibilityValue(glance?.battery ?? Strings.scooterNotAvailable)
                        .accessibilityIdentifier("scooter.battery")
                    Spacer(minLength: 12)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(verbatim: glance?.range ?? "–")
                            .font(.system(size: 30, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Theme.ink)
                        Text(Strings.scooterRange)
                            .font(.subheadline)
                            .foregroundStyle(Theme.muted)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Strings.scooterRange)
                    .accessibilityValue(glance?.range ?? Strings.scooterNotAvailable)
                    .accessibilityIdentifier("scooter.range")
                }
                HStack(spacing: 8) {
                    Circle()
                        .fill(dotColor)
                        .frame(width: 10, height: 10)
                    Text(glance?.status ?? Strings.scooterStatusNotSetUp)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("settings.scooter.status")
                Label {
                    Text(chargingText)
                } icon: {
                    Image(systemName: isCharging ? "bolt.fill" : "bolt.slash")
                        .foregroundStyle(isCharging ? Theme.connected : Theme.muted)
                }
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.body)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("settings.scooter.charging")
                if let fullIn = summary.fullIn {
                    Text(fullIn)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.connected)
                        .accessibilityIdentifier("scooter.fullIn")
                }
                if case let .failed(error) = scooter.state {
                    Text(Strings.scooterError(error))
                        .font(.subheadline)
                        .foregroundStyle(Theme.dangerText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("settings.scooter.error")
                }
            }
            .padding(.vertical, 6)
        }
    }

    private var dotColor: Color {
        switch glance?.link {
        case .connected: Theme.connected
        case .connecting: Theme.unverified
        case .offline, nil: Theme.muted
        }
    }

    private var controlsSection: some View {
        Section {
            HStack(spacing: 10) {
                controlTile(Strings.scooterOpenSeat, symbol: "tray.and.arrow.up.fill", tint: Theme.verified, id: "settings.scooter.openSeat") {
                    perform(.openSeat)
                }
                controlTile(Strings.scooterPowerOn, symbol: "power", tint: Theme.connected, id: "settings.scooter.powerOn") {
                    perform(.powerOn)
                }
                controlTile(Strings.scooterPowerOff, symbol: "power", tint: Theme.danger, id: "settings.scooter.powerOff") {
                    confirmingPowerOff = true
                }
                .disabled(!VehicleControl.powerOffAllowed(rideActive: scooter.rideActive, speedKmh: scooter.telemetry?.speedKmh))
            }
            .disabled(!canControl || scooter.state != .connected || busy)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            if let actionMessage {
                Text(actionMessage)
                    .accessibilityIdentifier("settings.scooter.actionResult")
            }
        } footer: {
            Text(Strings.scooterControlsFooter)
        }
    }

    private func controlTile(_ title: String, symbol: String, tint: Color, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 24, weight: .semibold))
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 84)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: 16))
        .tint(tint)
        .accessibilityIdentifier(id)
    }

    private var batterySection: some View {
        Section {
            summaryRow(Strings.scooterHealth, summary.health, id: "scooter.health")
            summaryRow(Strings.scooterCycles, summary.cycles, id: "scooter.cycles")
            summaryRow(Strings.scooterTemperature, summary.temperature, id: "scooter.temperature")
            NavigationLink {
                ScooterBatteryDetailsView(settings: settings, readings: readings)
            } label: {
                Text(Strings.scooterDetails)
                    .font(.system(size: 17, weight: .semibold))
            }
            .frame(minHeight: 44)
            .accessibilityIdentifier("scooter.battery.details")
        } header: {
            Text(Strings.scooterBatterySection)
        }
    }

    private func summaryRow(_ title: String, _ value: String?, id: String) -> some View {
        LabeledContent(title, value: value ?? Strings.scooterNotAvailable)
            .accessibilityIdentifier(id)
    }

    private var isCharging: Bool {
        readings.report?.isCharging ?? readings.charge.isCharging
    }

    private var chargingText: String {
        let target = settings.chargeNotifyTarget
        if let battery = readings.report, let charging = battery.isCharging {
            guard charging, let current = battery.currentA else { return Strings.scooterNotCharging }
            let amps = Strings.scooterChargingCurrent(ScooterBatterySummary.number("%.1f A", -current, language: settings.language))
            guard let eta = battery.estimatedTime(reaching: target, from: Date()) else { return amps }
            return amps + " · " + Strings.scooterChargingEta(target, Format.clockTime(eta))
        }
        let charge = readings.charge
        guard charge.isCharging else { return Strings.scooterNotCharging }
        guard let rate = charge.ratePerHour else { return Strings.scooterCharging }
        let rateText = Strings.scooterChargingRate(ScooterBatterySummary.number("%.1f%%", rate, language: settings.language))
        guard let eta = charge.estimatedTime(reaching: Double(target)) else { return rateText }
        return rateText + " · " + Strings.scooterChargingEta(target, Format.clockTime(eta))
    }

    private var notifySection: some View {
        Section {
            Toggle(isOn: notifyBinding) {
                Text(Strings.scooterNotify)
                    .font(.system(size: 17, weight: .semibold))
            }
            .tint(Theme.verified)
            .frame(minHeight: 44)
            .accessibilityIdentifier("settings.scooter.notify")

            Picker(Strings.scooterNotifyTarget, selection: $settings.chargeNotifyTarget) {
                ForEach(AppSettings.chargeTargets, id: \.self) { target in
                    Text(verbatim: "\(target)%").tag(target)
                }
            }
            .pickerStyle(.segmented)
            .disabled(!settings.chargeNotify)
            .accessibilityIdentifier("settings.scooter.notifyTarget")
        } footer: {
            Text(notifyDenied ? Strings.scooterNotifyDenied : Strings.scooterNotifyFooter)
        }
    }

    private var notifyBinding: Binding<Bool> {
        Binding(get: { settings.chargeNotify }, set: { on in
            guard on else {
                settings.chargeNotify = false
                return
            }
            Task {
                let allowed = await ChargeNotifier.requestPermission()
                notifyDenied = !allowed
                settings.chargeNotify = allowed
            }
        })
    }

    private var rangeSection: some View {
        Section {
            Stepper(value: $settings.rangeMarginPercent, in: AppSettings.rangeMarginRange, step: 5) {
                Text(Strings.rangeMargin(settings.rangeMarginPercent))
                    .font(.system(size: 17, weight: .semibold))
            }
            .frame(minHeight: 44)
            .accessibilityIdentifier("settings.rangeMargin")

            Toggle(isOn: $settings.turnBackWarning) {
                Text(Strings.turnBackWarning)
                    .font(.system(size: 17, weight: .semibold))
            }
            .tint(Theme.verified)
            .frame(minHeight: 44)
            .accessibilityIdentifier("settings.turnBackWarning")
        } header: {
            Text(Strings.scooterRangeSection)
        }
    }

    private var advancedSection: some View {
        Section {
            NavigationLink {
                ScooterAdvancedView(settings: settings)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Strings.scooterAdvanced)
                        .font(.system(size: 17, weight: .semibold))
                    Text(Strings.scooterAdvancedHint)
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                }
                .padding(.vertical, 4)
            }
            .accessibilityIdentifier("scooter.advanced")
        }
    }

    private var connectionSection: some View {
        Section {
            LabeledContent(Strings.scooterOdometer, value: scooter.telemetry.map { Format.distance(meters: Int(($0.odometerKm * 1000).rounded())) } ?? Strings.scooterNotAvailable)
                .accessibilityIdentifier("scooter.odometer")
            Button {
                scooter.restart()
            } label: {
                Text(scooter.state == .connecting ? Strings.scooterReading : Strings.scooterRead)
                    .font(.system(size: 17, weight: .semibold))
            }
            .frame(minHeight: 44)
            .disabled(!scooter.isConfigured || scooter.state == .connecting)
            .accessibilityIdentifier("settings.scooter.read")
        } header: {
            Text(Strings.scooterConnection)
        }
    }

    private var pairingSection: some View {
        Section {
            TextField(Strings.scooterSerial, text: $settings.scooterSerial)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .font(.system(size: 17, weight: .semibold))
                .frame(minHeight: 44)
                .onSubmit { scooter.restart() }
                .accessibilityIdentifier("settings.scooter.serial")

            secretField(hasPassword ? Strings.scooterPasswordSaved : Strings.scooterPassword, text: $passwordInput, id: "settings.scooter.password") { bytes in
                guard keychain.save(bytes, as: .password) else { return }
                hasPassword = true
                passwordInvalid = false
                scooter.restart()
            } invalid: { passwordInvalid = true }

            secretField(hasIdent ? Strings.scooterIdentSaved : Strings.scooterIdent, text: $identInput, id: "settings.scooter.ident") { bytes in
                guard keychain.save(bytes, as: .ident) else { return }
                hasIdent = true
                canControl = true
                identInvalid = false
            } invalid: { identInvalid = true }
        } header: {
            Text(Strings.scooterPairing)
        } footer: {
            if passwordInvalid {
                Text(Strings.scooterPasswordInvalid)
            } else if identInvalid {
                Text(Strings.scooterIdentInvalid)
            } else {
                Text(Strings.scooterFooter)
            }
        }
    }

    private func secretField(_ title: String, text: Binding<String>, id: String, save: @escaping ([UInt8]) -> Void, invalid: @escaping () -> Void) -> some View {
        SecureField(title, text: text)
            .font(.system(size: 17, weight: .semibold))
            .frame(minHeight: 44)
            .onChange(of: text.wrappedValue) { _, value in
                guard let bytes = ScooterPassword.parse(value) else { return }
                save(bytes)
                text.wrappedValue = ""
            }
            .onSubmit {
                if !text.wrappedValue.isEmpty { invalid() }
            }
            .accessibilityIdentifier(id)
    }

    private func perform(_ action: VehicleAction) {
        guard let ident = scooter.vehicleIdent else { return }
        busy = true
        actionMessage = nil
        let rideActive = scooter.rideActive
        let speed = scooter.telemetry?.speedKmh
        Task {
            defer { busy = false }
            do {
                let outcome = try await scooter.run {
                    try await VehicleControl.perform(action, ident: ident, session: $0, rideActive: rideActive, speedKmh: speed)
                }
                actionMessage = Strings.scooterActionOutcome(outcome)
            } catch ScooterControlError.powerOffWhileRiding {
                actionMessage = Strings.scooterRidingBlocked
            } catch {
                actionMessage = Strings.scooterError(error as? ScooterError ?? .unexpectedResponse)
            }
        }
    }
}

struct ScooterBatteryDetailsView: View {
    let settings: AppSettings
    let readings: ScooterBatteryReadings
    @Environment(ScooterConnection.self) private var scooter

    var body: some View {
        let battery = readings.report
        List {
            Section {
                row(Strings.scooterCharge, battery?.chargePercent.map { number("%.1f%%", $0) }, id: "scooter.details.charge")
                row(Strings.scooterVoltage, battery?.voltage.map { number("%.2f V", $0) }, id: "scooter.details.voltage")
                row(Strings.scooterCurrent, battery?.currentA.map { number("%.2f A", $0) }, id: "scooter.details.current")
                row(Strings.scooterCapacity, battery.flatMap(capacityText), id: "scooter.details.capacity")
                row(Strings.scooterHealth, battery?.healthPercent.map { number("%.0f%%", $0) }, id: "scooter.details.health")
                row(Strings.scooterCycles, battery?.cycles.map(String.init), id: "scooter.details.cycles")
                row(Strings.scooterChargeCount, battery?.chargeCount.map(String.init), id: "scooter.details.chargeCount")
                row(Strings.scooterTemperature, battery.flatMap { ScooterBatterySummary.temperature($0.temperaturesC) }, id: "scooter.details.temperature")
                row(Strings.scooterCells, battery.flatMap(cellsText), id: "scooter.details.cells")
                row(Strings.scooterPackSerial, battery?.serial, id: "scooter.details.serial")
                row(Strings.scooterFirmware, battery?.firmware, id: "scooter.details.firmware")
                row(Strings.scooterManufactured, battery?.manufactured.flatMap(dateText), id: "scooter.details.manufactured")
            } footer: {
                Text(Strings.scooterBatteryFooter)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Strings.scooterBatterySection)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: scooter.state == .connected) {
            guard scooter.state == .connected else { return }
            await readings.keepFresh(scooter)
        }
    }

    private func row(_ title: String, _ value: String?, id: String) -> some View {
        LabeledContent(title, value: value ?? Strings.scooterNotAvailable)
            .accessibilityIdentifier(id)
    }

    private func number(_ format: String, _ value: Double) -> String {
        ScooterBatterySummary.number(format, value, language: settings.language)
    }

    private func capacityText(_ report: BatteryReport) -> String? {
        guard let remaining = report.remainingAh, let full = report.fullCapacityAh else { return nil }
        return Strings.scooterCapacityValue(number("%.2f", remaining), number("%.2f Ah", full))
    }

    private func cellsText(_ report: BatteryReport) -> String? {
        guard let low = report.cellsMv.min(), let high = report.cellsMv.max(), let spread = report.cellSpreadMv else { return nil }
        return Strings.scooterCellsValue(report.cellsMv.count, low, high, spread)
    }

    private func dateText(_ components: DateComponents) -> String? {
        guard let date = Calendar(identifier: .gregorian).date(from: components) else { return nil }
        return date.formatted(Date.FormatStyle(date: .long, time: .omitted).locale(settings.language.locale))
    }
}
