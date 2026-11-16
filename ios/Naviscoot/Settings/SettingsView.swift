import AVFoundation
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @Environment(ScooterConnection.self) private var scooter

    var body: some View {
        NavigationStack {
            Form {
                scooterSection

                Section {
                    Picker(Strings.languageSection, selection: $settings.languageChoice) {
                        ForEach(LanguageChoice.allCases) { choice in
                            Text(Strings.languageName(choice))
                                .font(.system(size: 18, weight: .semibold))
                                .tag(choice)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    .accessibilityIdentifier("settings.language")
                } header: {
                    Text(Strings.languageSection)
                } footer: {
                    Text(Strings.languageFooter)
                }

                Section {
                    Toggle(isOn: $settings.verifiedOnlyByDefault) {
                        Text(Strings.verifiedOnlyDefault)
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .tint(Theme.verified)
                    .frame(minHeight: 52)
                    .accessibilityIdentifier("settings.verifiedOnlyDefault")
                } header: {
                    Text(Strings.routeSection)
                } footer: {
                    Text(Strings.verifiedOnlyDefaultFooter)
                }

                Section {
                    settingToggle(Strings.avoidFerries, isOn: $settings.avoidFerries, id: "settings.avoidFerries")
                    settingToggle(Strings.avoidUnpaved, isOn: $settings.avoidUnpaved, id: "settings.avoidUnpaved")
                    settingToggle(Strings.avoidMainRoads, isOn: $settings.avoidMainRoads, id: "settings.avoidMainRoads")
                } header: {
                    Text(Strings.avoidSection)
                } footer: {
                    Text(Strings.avoidFooter)
                }

                Section {
                    Picker(Strings.appearanceSection, selection: $settings.appearance) {
                        ForEach(AppearanceChoice.allCases) { choice in
                            Text(Strings.appearanceName(choice))
                                .font(.system(size: 18, weight: .semibold))
                                .tag(choice)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    .accessibilityIdentifier("settings.appearance")
                } header: {
                    Text(Strings.appearanceSection)
                }

                Section {
                    Picker(Strings.mapStyleSection, selection: $settings.mapStyle) {
                        ForEach(MapStyle.allCases) { style in
                            Text(Strings.mapStyleName(style))
                                .font(.system(size: 18, weight: .semibold))
                                .tag(style)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    .accessibilityIdentifier("settings.mapStyle")
                } header: {
                    Text(Strings.mapStyleSection)
                } footer: {
                    Text(Strings.mapStyleFooter)
                }

                Section {
                    settingToggle(Strings.darkMapAtNight, isOn: $settings.darkMapAtNight, id: "settings.darkMapAtNight")
                    settingToggle(Strings.northUp, isOn: $settings.northUp, id: "settings.northUp")
                    settingToggle(Strings.threeD, isOn: $settings.threeD, id: "settings.threeD")
                    settingToggle(Strings.autoZoom, isOn: $settings.autoZoom, id: "settings.autoZoom")
                } header: {
                    Text(Strings.mapSection)
                } footer: {
                    Text(Strings.mapFooter)
                }

                Section {
                    Picker(Strings.voiceSection, selection: $settings.guidanceMode) {
                        ForEach(GuidanceMode.allCases) { mode in
                            Text(Strings.guidanceModeName(mode))
                                .font(.system(size: 18, weight: .semibold))
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    .accessibilityIdentifier("settings.guidanceMode")

                    Picker(selection: voiceSelection) {
                        Text(Strings.defaultVoice(GuidanceVoices.defaultVoice(for: settings.language)?.name))
                            .tag("")
                            .accessibilityIdentifier("settings.voice.default")
                        ForEach(GuidanceVoices.installed(for: settings.language), id: \.identifier) { voice in
                            Text(verbatim: voiceLabel(voice))
                                .tag(voice.identifier)
                                .accessibilityIdentifier("settings.voice.\(voice.identifier)")
                        }
                    } label: {
                        Text(Strings.voice)
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .pickerStyle(.navigationLink)
                    .frame(minHeight: 52)
                    .accessibilityIdentifier("settings.voice")

                    settingStepper(
                        Strings.speechRate(settings.speechRatePercent),
                        value: $settings.speechRatePercent,
                        in: SpeechSettings.ratePercentRange,
                        step: SpeechSettings.percentStep,
                        id: "settings.speechRate"
                    )
                    settingStepper(
                        Strings.speechVolume(settings.speechVolumePercent),
                        value: $settings.speechVolumePercent,
                        in: SpeechSettings.volumePercentRange,
                        step: SpeechSettings.percentStep,
                        id: "settings.speechVolume"
                    )
                } header: {
                    Text(Strings.voiceSection)
                } footer: {
                    Text(Strings.voiceFooter)
                }

                Section {
                    settingToggle(Strings.speedingAlert, isOn: $settings.speedingAlert, id: "settings.speedingAlert")
                    settingStepper(
                        Strings.speedingTolerance(settings.speedingToleranceKmh),
                        value: $settings.speedingToleranceKmh,
                        in: AppSettings.speedingToleranceRange,
                        step: 1,
                        id: "settings.speedingTolerance"
                    )
                } header: {
                    Text(Strings.speedingSection)
                } footer: {
                    Text(Strings.speedingFooter)
                }

                Section {
                    LabeledContent(Strings.version, value: Self.version)
                } header: {
                    Text(Strings.aboutSection)
                }
            }
            .navigationTitle(Strings.settingsTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(Strings.done) { dismiss() }
                        .font(.system(size: 18, weight: .bold))
                        .accessibilityIdentifier("settings.done")
                }
            }
        }
    }

    private var scooterSection: some View {
        Section {
            NavigationLink {
                ScooterScreen(settings: settings)
            } label: {
                LabeledContent {
                    Text(ScooterStatus.text(scooter.state, telemetry: scooter.telemetry))
                } label: {
                    Text(Strings.scooterSection)
                        .font(.system(size: 18, weight: .semibold))
                }
            }
            .frame(minHeight: 52)
            .accessibilityIdentifier("settings.scooter")
        }
    }

    private func settingToggle(_ title: String, isOn: Binding<Bool>, id: String) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .font(.system(size: 18, weight: .semibold))
        }
        .tint(Theme.verified)
        .frame(minHeight: 52)
        .accessibilityIdentifier(id)
    }

    private var voiceSelection: Binding<String> {
        Binding(
            get: { settings.voiceIdentifier(for: settings.language) ?? "" },
            set: { settings.setVoiceIdentifier($0.isEmpty ? nil : $0, for: settings.language) }
        )
    }

    private func voiceLabel(_ voice: AVSpeechSynthesisVoice) -> String {
        let region = Locale(identifier: voice.language).region.flatMap { settings.language.locale.localizedString(forRegionCode: $0.identifier) }
        return [voice.name, region].compactMap { $0 }.joined(separator: " · ")
    }

    private func settingStepper(_ title: String, value: Binding<Int>, in range: ClosedRange<Int>, step: Int, id: String) -> some View {
        Stepper(value: value, in: range, step: step) {
            Text(title)
                .font(.system(size: 18, weight: .semibold))
        }
        .frame(minHeight: 52)
        .accessibilityIdentifier(id)
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}
