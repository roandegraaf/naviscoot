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
                navigationSections
                routeDefaultsSections
                mapSections
                generalSection

                Section {
                    LabeledContent(Strings.version, value: Self.version)
                } header: {
                    sectionHeader(Strings.aboutSection, id: "settings.section.about")
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

    @ViewBuilder
    private var navigationSections: some View {
        Section {
            VoiceModePicker(selection: $settings.guidanceMode, id: "settings.voiceMode")
                .labelsHidden()
                .frame(minHeight: 44)

            NavigationLink {
                VoiceSettingsView(settings: settings)
            } label: {
                LabeledContent {
                    Text(verbatim: currentVoiceName)
                } label: {
                    Text(Strings.voice)
                        .font(.system(size: 18, weight: .semibold))
                }
            }
            .frame(minHeight: 52)
            .accessibilityIdentifier("settings.voiceDetails")
        } header: {
            sectionHeader(Strings.navigationSection, id: "settings.section.navigation")
        } footer: {
            Text(Strings.voiceModeFooter)
        }

        Section {
            settingToggle(Strings.speedingAlert, isOn: $settings.speedingAlert, id: "settings.speedingAlert")
            SettingStepper(
                title: Strings.speedingTolerance(settings.speedingToleranceKmh),
                value: $settings.speedingToleranceKmh,
                range: AppSettings.speedingToleranceRange,
                step: 1,
                id: "settings.speedingTolerance"
            )
        } footer: {
            Text(Strings.speedingFooter)
        }
    }

    @ViewBuilder
    private var routeDefaultsSections: some View {
        Section {
            settingToggle(Strings.verifiedOnlyDefault, isOn: $settings.verifiedOnlyByDefault, id: "settings.verifiedOnlyDefault")
        } header: {
            sectionHeader(Strings.routeDefaultsSection, id: "settings.section.routeDefaults")
        } footer: {
            Text(Strings.verifiedOnlyDefaultFooter)
        }

        Section {
            settingToggle(Strings.avoidFerries, isOn: $settings.avoidFerries, id: "settings.avoidFerries")
            settingToggle(Strings.avoidUnpaved, isOn: $settings.avoidUnpaved, id: "settings.avoidUnpaved")
            settingToggle(Strings.avoidMainRoads, isOn: $settings.avoidMainRoads, id: "settings.avoidMainRoads")
        } footer: {
            Text(Strings.avoidFooter)
        }
    }

    @ViewBuilder
    private var mapSections: some View {
        Section {
            MapStyleCards(selection: $settings.mapStyle, idPrefix: "settings.mapStyle", horizontalPadding: 20)
                .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0))
                .accessibilityIdentifier("settings.mapStyle")
        } header: {
            sectionHeader(Strings.mapGroupSection, id: "settings.section.map")
        } footer: {
            Text(Strings.mapStyleFooter)
        }

        Section {
            settingToggle(Strings.darkMapAtNight, isOn: $settings.darkMapAtNight, id: "settings.darkMapAtNight")
            settingToggle(Strings.northUp, isOn: $settings.northUp, id: "settings.northUp")
            settingToggle(Strings.threeD, isOn: $settings.threeD, id: "settings.threeD")
            settingToggle(Strings.autoZoom, isOn: $settings.autoZoom, id: "settings.autoZoom")
        } footer: {
            Text(Strings.mapFooter)
        }
    }

    private var generalSection: some View {
        Section {
            Picker(selection: $settings.languageChoice) {
                ForEach(LanguageChoice.allCases) { choice in
                    Text(Strings.languageName(choice)).tag(choice)
                }
            } label: {
                Text(Strings.languageSection)
                    .font(.system(size: 18, weight: .semibold))
            }
            .pickerStyle(.menu)
            .frame(minHeight: 52)
            .accessibilityIdentifier("settings.language")

            Picker(selection: $settings.appearance) {
                ForEach(AppearanceChoice.allCases) { choice in
                    Text(Strings.appearanceName(choice)).tag(choice)
                }
            } label: {
                Text(Strings.appearanceSection)
                    .font(.system(size: 18, weight: .semibold))
            }
            .pickerStyle(.menu)
            .frame(minHeight: 52)
            .accessibilityIdentifier("settings.appearance")
        } header: {
            sectionHeader(Strings.generalSection, id: "settings.section.general")
        } footer: {
            Text(Strings.languageFooter)
        }
    }

    private var currentVoiceName: String {
        let identifier = settings.voiceIdentifier(for: settings.language)
        let voice = identifier.flatMap(AVSpeechSynthesisVoice.init(identifier:)) ?? GuidanceVoices.defaultVoice(for: settings.language)
        return voice?.name ?? Strings.defaultVoice(nil)
    }

    private func sectionHeader(_ title: String, id: String) -> some View {
        Text(title)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier(id)
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

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}

private struct VoiceSettingsView: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section {
                SettingStepper(
                    title: Strings.speechRate(settings.speechRatePercent),
                    value: $settings.speechRatePercent,
                    range: SpeechSettings.ratePercentRange,
                    step: SpeechSettings.percentStep,
                    id: "settings.speechRate"
                )
                SettingStepper(
                    title: Strings.speechVolume(settings.speechVolumePercent),
                    value: $settings.speechVolumePercent,
                    range: SpeechSettings.volumePercentRange,
                    step: SpeechSettings.percentStep,
                    id: "settings.speechVolume"
                )
            }

            Section {
                Picker(Strings.voice, selection: voiceSelection) {
                    Text(Strings.defaultVoice(GuidanceVoices.defaultVoice(for: settings.language)?.name))
                        .tag("")
                        .accessibilityIdentifier("settings.voice.default")
                    ForEach(GuidanceVoices.installed(for: settings.language), id: \.identifier) { voice in
                        Text(verbatim: voiceLabel(voice))
                            .tag(voice.identifier)
                            .accessibilityIdentifier("settings.voice.\(voice.identifier)")
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } footer: {
                Text(Strings.voiceListFooter)
            }
        }
        .navigationTitle(Strings.voice)
        .navigationBarTitleDisplayMode(.inline)
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
}

private struct SettingStepper: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    let id: String

    var body: some View {
        Stepper(value: $value, in: range, step: step) {
            Text(title)
                .font(.system(size: 18, weight: .semibold))
        }
        .frame(minHeight: 52)
        .accessibilityIdentifier(id)
    }
}
