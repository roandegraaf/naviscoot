import SwiftUI

struct ScooterSettingsView: View {
    @Bindable var settings: AppSettings
    @Environment(ScooterConnection.self) private var scooter
    @State private var hasPassword = false
    @State private var hasIdent = false
    @State private var passwordInput = ""
    @State private var identInput = ""
    @State private var passwordInvalid = false
    @State private var identInvalid = false
    @State private var battery: BatteryReport?
    @State private var charge = ChargeTracker()
    @State private var notifyDenied = false
    @State private var actionMessage: String?
    @State private var confirmingPowerOff = false
    @State private var currentLimit: Int?
    @State private var ratedKmh: Int?
    @State private var newLimit = 0
    @State private var speedMessage: String?
    @State private var topSpeed: TopSpeedState?
    @State private var topSpeedMessage: String?
    @State private var features: [ScooterFeature.ID: Bool] = [:]
    @State private var featureMessage: String?
    @State private var recovery: EnergyRecovery?
    @State private var busy = false
    private let keychain = ScooterKeychain()

    var body: some View {
        Form {
            connectionSection
            rangeSection
            batterySection
            notifySection
            controlsSection
            featuresSection
            speedSection
            topSpeedSection
            pairingSection
        }
        .navigationTitle(Strings.scooterSection)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            hasPassword = keychain.value(.password) != nil
            hasIdent = keychain.value(.ident) != nil
        }
        .task(id: scooter.state == .connected) {
            guard scooter.state == .connected else { return }
            await readSpeedLimit()
            features = (try? await scooter.run { await ScooterFeatureControl.read(from: $0) }) ?? [:]
            recovery = (try? await scooter.run { await ScooterFeatureControl.readRecovery(from: $0) }) ?? nil
            while !Task.isCancelled {
                await readBattery()
                try? await Task.sleep(for: .seconds(10))
            }
        }
        .confirmationDialog(Strings.scooterPowerOffConfirm, isPresented: $confirmingPowerOff, titleVisibility: .visible) {
            Button(Strings.scooterPowerOff, role: .destructive) { perform(.powerOff) }
                .accessibilityIdentifier("settings.scooter.powerOff.confirm")
        }
    }

    private var connectionSection: some View {
        Section {
            LabeledContent(Strings.scooterConnection, value: ScooterStatus.text(scooter.state, telemetry: nil))
                .accessibilityIdentifier("settings.scooter.status")

            if let telemetry = scooter.telemetry, scooter.state == .connected {
                LabeledContent(Strings.scooterBattery, value: "\(telemetry.batteryPercent)%")
                LabeledContent(Strings.scooterRange, value: Format.distance(meters: Int((telemetry.rangeKm * 1000).rounded())))
                LabeledContent(Strings.scooterOdometer, value: Format.distance(meters: Int((telemetry.odometerKm * 1000).rounded())))
            } else if case let .failed(error) = scooter.state {
                Text(Strings.scooterError(error))
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("settings.scooter.error")
            }

            Button {
                scooter.restart()
            } label: {
                Text(scooter.state == .connecting ? Strings.scooterReading : Strings.scooterRead)
                    .font(.system(size: 18, weight: .bold))
            }
            .frame(minHeight: 52)
            .disabled(settings.scooterSerial.isEmpty || !hasPassword || scooter.state == .connecting)
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
                .font(.system(size: 18, weight: .semibold))
                .frame(minHeight: 52)
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

    private var rangeSection: some View {
        Section {
            Stepper(value: $settings.rangeMarginPercent, in: AppSettings.rangeMarginRange, step: 5) {
                Text(Strings.rangeMargin(settings.rangeMarginPercent))
                    .font(.system(size: 18, weight: .semibold))
            }
            .frame(minHeight: 52)
            .accessibilityIdentifier("settings.rangeMargin")

            Toggle(isOn: $settings.turnBackWarning) {
                Text(Strings.turnBackWarning)
                    .font(.system(size: 18, weight: .semibold))
            }
            .tint(Theme.verified)
            .frame(minHeight: 52)
            .accessibilityIdentifier("settings.turnBackWarning")
        } header: {
            Text(Strings.scooterRangeSection)
        }
    }

    private var batterySection: some View {
        Section {
            Text(chargingText)
                .accessibilityIdentifier("settings.scooter.charging")
            batteryRow(Strings.scooterCharge, battery?.chargePercent.map { number("%.1f%%", $0) })
            batteryRow(Strings.scooterVoltage, battery?.voltage.map { number("%.2f V", $0) })
            batteryRow(Strings.scooterCurrent, battery?.currentA.map { number("%.2f A", $0) })
            batteryRow(Strings.scooterCapacity, battery.flatMap(capacityText))
            batteryRow(Strings.scooterHealth, battery?.healthPercent.map { number("%.0f%%", $0) })
            batteryRow(Strings.scooterCycles, battery?.cycles.map(String.init))
            batteryRow(Strings.scooterChargeCount, battery?.chargeCount.map(String.init))
            batteryRow(Strings.scooterTemperature, battery.flatMap { temperatureText($0.temperaturesC) })
            batteryRow(Strings.scooterCells, battery.flatMap(cellsText))
            batteryRow(Strings.scooterPackSerial, battery?.serial)
            batteryRow(Strings.scooterFirmware, battery?.firmware)
            batteryRow(Strings.scooterManufactured, battery?.manufactured.flatMap(dateText))
        } header: {
            Text(Strings.scooterBatterySection)
        } footer: {
            Text(Strings.scooterBatteryFooter)
        }
    }

    private func batteryRow(_ title: String, _ value: String?) -> some View {
        LabeledContent(title, value: value ?? Strings.scooterNotAvailable)
    }

    private func number(_ format: String, _ value: Double) -> String {
        String(format: format, locale: settings.language.locale, value)
    }

    private func capacityText(_ report: BatteryReport) -> String? {
        guard let remaining = report.remainingAh, let full = report.fullCapacityAh else { return nil }
        return Strings.scooterCapacityValue(number("%.2f", remaining), number("%.2f Ah", full))
    }

    private func temperatureText(_ values: [Int]) -> String? {
        guard let low = values.min(), let high = values.max() else { return nil }
        return low == high ? "\(low) °C" : "\(low)–\(high) °C"
    }

    private func cellsText(_ report: BatteryReport) -> String? {
        guard let low = report.cellsMv.min(), let high = report.cellsMv.max(), let spread = report.cellSpreadMv else { return nil }
        return Strings.scooterCellsValue(report.cellsMv.count, low, high, spread)
    }

    private func dateText(_ components: DateComponents) -> String? {
        guard let date = Calendar(identifier: .gregorian).date(from: components) else { return nil }
        return date.formatted(Date.FormatStyle(date: .long, time: .omitted).locale(settings.language.locale))
    }

    private var chargingText: String {
        if let battery, let charging = battery.isCharging {
            guard charging, let current = battery.currentA else { return Strings.scooterNotCharging }
            let amps = Strings.scooterChargingCurrent(number("%.1f A", -current))
            guard let eta = battery.estimatedTime(reaching: settings.chargeNotifyTarget, from: Date()) else { return amps }
            return amps + " · " + Strings.scooterChargingEta(settings.chargeNotifyTarget, Format.clockTime(eta))
        }
        guard charge.isCharging else { return Strings.scooterNotCharging }
        guard let rate = charge.ratePerHour else { return Strings.scooterCharging }
        let rateText = Strings.scooterChargingRate(String(format: "%.1f%%", locale: settings.language.locale, rate))
        guard let eta = charge.estimatedTime(reaching: Double(settings.chargeNotifyTarget)) else { return rateText }
        return rateText + " · " + Strings.scooterChargingEta(settings.chargeNotifyTarget, Format.clockTime(eta))
    }

    private var notifySection: some View {
        Section {
            Toggle(isOn: notifyBinding) {
                Text(Strings.scooterNotify)
                    .font(.system(size: 18, weight: .semibold))
            }
            .tint(Theme.verified)
            .frame(minHeight: 52)
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

    private var controlsSection: some View {
        Section {
            actionButton(Strings.scooterOpenSeat, id: "settings.scooter.openSeat") { perform(.openSeat) }
            actionButton(Strings.scooterPowerOn, id: "settings.scooter.powerOn") { perform(.powerOn) }
            actionButton(Strings.scooterPowerOff, id: "settings.scooter.powerOff") { confirmingPowerOff = true }
                .disabled(!VehicleControl.powerOffAllowed(rideActive: scooter.rideActive, speedKmh: scooter.telemetry?.speedKmh))
            if let actionMessage {
                Text(actionMessage)
                    .accessibilityIdentifier("settings.scooter.actionResult")
            }
        } header: {
            Text(Strings.scooterControls)
        } footer: {
            Text(Strings.scooterControlsFooter)
        }
        .disabled(!hasIdent || scooter.state != .connected || busy)
    }

    private var featuresSection: some View {
        Section {
            if let recovery {
                Picker(selection: Binding(get: { recovery }, set: { applyRecovery($0) })) {
                    ForEach(EnergyRecovery.allCases, id: \.self) { level in
                        Text(Strings.scooterRecoveryLevel(level)).tag(level)
                    }
                } label: {
                    settingLabel(Strings.scooterRecovery, detail: Strings.scooterRecoveryFooter)
                }
                .frame(minHeight: 52)
                .accessibilityIdentifier("settings.scooter.recovery")
            }
            ForEach(ScooterFeature.all) { feature in
                if let on = features[feature.id] {
                    Toggle(isOn: Binding(get: { on }, set: { applyFeature(feature, on: $0) })) {
                        settingLabel(Strings.scooterFeature(feature.id), detail: Strings.scooterFeatureFooter(feature.id))
                    }
                    .tint(Theme.verified)
                    .frame(minHeight: 52)
                    .accessibilityIdentifier("settings.scooter.feature.\(feature.id.rawValue)")
                }
            }
            LabeledContent(Strings.scooterClock, value: scooter.clockSync.map(Strings.scooterClockState) ?? Strings.scooterNotAvailable)
                .accessibilityIdentifier("settings.scooter.clock")
            if let featureMessage {
                Text(featureMessage)
                    .accessibilityIdentifier("settings.scooter.featureResult")
            }
        } header: {
            Text(Strings.scooterFeatures)
        } footer: {
            Text(Strings.scooterFeaturesFooter)
        }
        .disabled(scooter.state != .connected || busy || !ScooterFeatureControl.changeAllowed(rideActive: scooter.rideActive, speedKmh: scooter.telemetry?.speedKmh))
    }

    private var speedSection: some View {
        Section {
            LabeledContent(Strings.scooterSpeedCurrent, value: currentLimit.map(Strings.scooterSpeedLimit) ?? Strings.scooterNotAvailable)
                .accessibilityIdentifier("settings.scooter.speedCurrent")
            if let ratedKmh {
                Picker(Strings.scooterSpeedNew, selection: $newLimit) {
                    ForEach(SpeedLimitControl.choices(ratedKmh: ratedKmh), id: \.self) { limit in
                        Text(Strings.scooterSpeedLimit(limit)).tag(limit)
                    }
                }
                .frame(minHeight: 52)
                .accessibilityIdentifier("settings.scooter.speedNew")
                actionButton(Strings.scooterSpeedApply, id: "settings.scooter.speedApply") { applyLimit(newLimit) }
                    .disabled(newLimit == currentLimit)
                if let original = settings.scooterOriginalSpeedLimit, original != currentLimit {
                    actionButton(Strings.scooterSpeedRestore(Strings.scooterSpeedLimit(original)), id: "settings.scooter.speedRestore") { applyLimit(original) }
                }
            }
            if let speedMessage {
                Text(speedMessage)
                    .accessibilityIdentifier("settings.scooter.speedResult")
            }
        } header: {
            Text(Strings.scooterSpeed)
        } footer: {
            Text(Strings.scooterSpeedFooter(ratedKmh ?? 45))
        }
        .disabled(scooter.state != .connected || busy)
    }

    private var topSpeedSection: some View {
        Section {
            LabeledContent(Strings.scooterTopSpeedCurrent, value: topSpeed.map { Strings.scooterTopSpeedState($0) } ?? Strings.scooterNotAvailable)
                .accessibilityIdentifier("settings.scooter.topSpeedCurrent")
            if let topSpeed {
                Toggle(isOn: Binding(get: { topSpeed == .unlocked }, set: { applyTopSpeed(unlocked: $0) })) {
                    Text(Strings.scooterTopSpeedUnlock)
                        .font(.system(size: 18, weight: .semibold))
                }
                .tint(Theme.verified)
                .frame(minHeight: 52)
                .accessibilityIdentifier("settings.scooter.topSpeedUnlock")
            }
            if let topSpeedMessage {
                Text(topSpeedMessage)
                    .accessibilityIdentifier("settings.scooter.topSpeedResult")
            }
        } header: {
            Text(Strings.scooterTopSpeed)
        } footer: {
            Text(Strings.scooterTopSpeedFooter)
        }
        .disabled(scooter.state != .connected || busy)
    }

    private func secretField(_ title: String, text: Binding<String>, id: String, save: @escaping ([UInt8]) -> Void, invalid: @escaping () -> Void) -> some View {
        SecureField(title, text: text)
            .font(.system(size: 18, weight: .semibold))
            .frame(minHeight: 52)
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

    private func settingLabel(_ title: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 18, weight: .semibold))
            if let detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 6)
    }

    private func actionButton(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 18, weight: .bold))
        }
        .frame(minHeight: 52)
        .accessibilityIdentifier(id)
    }

    private func readBattery() async {
        guard let report = try? await scooter.run({ await BatteryReport.read(from: $0) }) else { return }
        battery = report
        if let percent = report.chargePercent { charge.record(percent, at: Date()) }
    }

    private func readSpeedLimit() async {
        let values = try? await scooter.run { session in
            (try? await session.value(.speedLimit), try? await session.value(.ratedSpeed))
        }
        currentLimit = values?.0
        ratedKmh = values?.1.map(SpeedLimitControl.ratedKmh(fromRegister:))
        newLimit = currentLimit ?? 0
        topSpeed = (try? await scooter.run { try? await $0.value(.topSpeed) }).flatMap { $0 }.map(TopSpeedState.init(register:))
    }

    private func applyTopSpeed(unlocked: Bool) {
        busy = true
        topSpeedMessage = nil
        let original = settings.scooterOriginalTopSpeed
        Task {
            defer { busy = false }
            do {
                let outcome = try await scooter.run {
                    try await TopSpeedControl.apply(unlocked: unlocked, original: original, session: $0)
                }
                if settings.scooterOriginalTopSpeed == nil { settings.scooterOriginalTopSpeed = outcome.original }
                topSpeedMessage = Strings.scooterTopSpeedWrite(outcome.result)
                if case let .confirmed(state) = outcome.result { topSpeed = state }
                if case let .mismatch(state) = outcome.result { topSpeed = state }
            } catch {
                topSpeedMessage = Strings.scooterError(error as? ScooterError ?? .unexpectedResponse)
            }
        }
    }

    private func applyFeature(_ feature: ScooterFeature, on: Bool) {
        busy = true
        featureMessage = nil
        let rideActive = scooter.rideActive
        let speed = scooter.telemetry?.speedKmh
        Task {
            defer { busy = false }
            do {
                let result = try await scooter.run {
                    try await ScooterFeatureControl.apply(feature, on: on, session: $0, rideActive: rideActive, speedKmh: speed)
                }
                featureMessage = Strings.scooterFeatureWrite(feature.id, result)
                if case let .confirmed(state) = result { features[feature.id] = state }
                if case let .mismatch(state) = result { features[feature.id] = state }
            } catch ScooterControlError.settingWhileRiding {
                featureMessage = Strings.scooterSettingWhileRiding
            } catch {
                featureMessage = Strings.scooterError(error as? ScooterError ?? .unexpectedResponse)
            }
        }
    }

    private func applyRecovery(_ level: EnergyRecovery) {
        busy = true
        featureMessage = nil
        let rideActive = scooter.rideActive
        let speed = scooter.telemetry?.speedKmh
        Task {
            defer { busy = false }
            do {
                let result = try await scooter.run {
                    try await ScooterFeatureControl.apply(level, session: $0, rideActive: rideActive, speedKmh: speed)
                }
                featureMessage = Strings.scooterRecoveryWrite(result)
                if case let .confirmed(state) = result { recovery = state }
                if case let .mismatch(state) = result { recovery = state }
            } catch ScooterControlError.settingWhileRiding {
                featureMessage = Strings.scooterSettingWhileRiding
            } catch {
                featureMessage = Strings.scooterError(error as? ScooterError ?? .unexpectedResponse)
            }
        }
    }

    private func perform(_ action: VehicleAction) {
        guard let ident = keychain.value(.ident) else { return }
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

    private func applyLimit(_ limit: Int) {
        guard let ratedKmh else { return }
        busy = true
        speedMessage = nil
        let original = settings.scooterOriginalSpeedLimit
        Task {
            defer { busy = false }
            do {
                let outcome = try await scooter.run {
                    try await SpeedLimitControl.apply(limit, ratedKmh: ratedKmh, original: original, session: $0)
                }
                if settings.scooterOriginalSpeedLimit == nil { settings.scooterOriginalSpeedLimit = outcome.original }
                speedMessage = Strings.scooterSpeedWrite(outcome.result)
                if case let .confirmed(value) = outcome.result { currentLimit = value }
                if case let .mismatch(value) = outcome.result { currentLimit = value }
            } catch {
                speedMessage = Strings.scooterError(error as? ScooterError ?? .unexpectedResponse)
            }
        }
    }
}

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
