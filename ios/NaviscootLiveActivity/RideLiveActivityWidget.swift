import ActivityKit
import SwiftUI
import WidgetKit

@main
struct NaviscootWidgets: WidgetBundle {
    var body: some Widget {
        RideLiveActivityWidget()
    }
}

private enum Palette {
    static let fill = Color(red: 0x11 / 255, green: 0x18 / 255, blue: 0x27 / 255)
    static let maneuver = Color(red: 0x3B / 255, green: 0x82 / 255, blue: 0xF6 / 255)
    static let warning = Color(red: 0xF9 / 255, green: 0x73 / 255, blue: 0x16 / 255)
    static let warningText = Color(red: 0xFD / 255, green: 0xBA / 255, blue: 0x74 / 255)
    static let secondary = Color.white.opacity(0.72)
}

struct RideLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RideActivityAttributes.self) { context in
            LockScreenView(state: context.state)
                .opacity(context.isStale ? 0.55 : 1)
                .activityBackgroundTint(Palette.fill)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ManeuverIcon(symbol: state.symbol, size: 30)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(verbatim: state.arrival)
                            .font(.system(size: 20, weight: .heavy))
                            .monospacedDigit()
                        Text(verbatim: state.remaining)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Palette.secondary)
                        if let battery = state.battery {
                            BatteryLabel(text: battery)
                        }
                    }
                    .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        if !state.distance.isEmpty {
                            Text(verbatim: state.distance)
                                .font(.system(size: 24, weight: .heavy))
                                .monospacedDigit()
                        }
                        Text(verbatim: state.street)
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let warning = state.warning {
                        WarningRow(text: warning)
                    }
                }
            } compactLeading: {
                Image(systemName: state.symbol)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(state.warning == nil ? Palette.maneuver : Palette.warning)
            } compactTrailing: {
                Text(verbatim: state.arrived ? state.arrival : state.distance)
                    .font(.system(size: 15, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(state.warning == nil ? Color.white : Palette.warningText)
            } minimal: {
                Image(systemName: state.warning == nil ? state.symbol : "exclamationmark.triangle.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(state.warning == nil ? Palette.maneuver : Palette.warning)
            }
            .keylineTint(state.warning == nil ? Palette.maneuver : Palette.warning)
        }
    }
}

private struct LockScreenView: View {
    let state: RideActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                ManeuverIcon(symbol: state.symbol, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    if !state.distance.isEmpty {
                        Text(verbatim: state.distance)
                            .font(.system(size: 28, weight: .heavy))
                            .monospacedDigit()
                    }
                    Text(verbatim: state.street)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(verbatim: state.arrivalLabel)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.secondary)
                    Text(verbatim: state.arrival)
                        .font(.system(size: 22, weight: .heavy))
                        .monospacedDigit()
                    Text(verbatim: state.remaining)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.secondary)
                    if let battery = state.battery {
                        BatteryLabel(text: battery)
                    }
                }
            }
            if let warning = state.warning {
                WarningRow(text: warning)
            }
        }
        .foregroundStyle(.white)
        .padding(16)
    }
}

private struct ManeuverIcon: View {
    let symbol: String
    let size: CGFloat

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size * 1.6, height: size * 1.6)
            .background(Palette.maneuver, in: RoundedRectangle(cornerRadius: size * 0.4))
    }
}

private struct BatteryLabel: View {
    let text: String

    var body: some View {
        Label {
            Text(verbatim: text)
        } icon: {
            Image(systemName: "battery.75percent")
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(Palette.secondary)
        .labelStyle(.titleAndIcon)
    }
}

private struct WarningRow: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Palette.warning)
            Text(verbatim: text)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Palette.warningText)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
