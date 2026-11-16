import SwiftUI

struct ScooterAdvancedView: View {
    @Bindable var settings: AppSettings
    @Environment(ScooterConnection.self) private var scooter
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

    var body: some View {
        List {
            speedSection
            topSpeedSection
            featuresSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Strings.scooterAdvanced)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: scooter.state == .connected) {
            guard scooter.state == .connected else { return }
            await readSpeedLimit()
            features = (try? await scooter.run { await ScooterFeatureControl.read(from: $0) }) ?? [:]
            recovery = (try? await scooter.run { await ScooterFeatureControl.readRecovery(from: $0) }) ?? nil
        }
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
                .frame(minHeight: 44)
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
                        .font(.system(size: 17, weight: .semibold))
                }
                .tint(Theme.verified)
                .frame(minHeight: 44)
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
                .frame(minHeight: 44)
                .accessibilityIdentifier("settings.scooter.recovery")
            }
            ForEach(ScooterFeature.all) { feature in
                if let on = features[feature.id] {
                    Toggle(isOn: Binding(get: { on }, set: { applyFeature(feature, on: $0) })) {
                        settingLabel(Strings.scooterFeature(feature.id), detail: Strings.scooterFeatureFooter(feature.id))
                    }
                    .tint(Theme.verified)
                    .frame(minHeight: 44)
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

    private func settingLabel(_ title: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
            if let detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }

    private func actionButton(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
        }
        .frame(minHeight: 44)
        .accessibilityIdentifier(id)
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
