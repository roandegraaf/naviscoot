import SwiftUI

struct WatchRideView: View {
    let message: WatchRideMessage?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            if let message, let state = message.state {
                riding(state)
                    .opacity(message.isStale(now: context.date) ? 0.45 : 1)
            } else {
                idle
            }
        }
    }

    private func riding(_ state: WatchRideState) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: state.symbol)
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(Palette.maneuver)
                        .accessibilityIdentifier("watch.symbol")
                    if !state.distance.isEmpty {
                        Text(verbatim: state.distance)
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                            .accessibilityIdentifier("watch.distance")
                    }
                }
                Text(verbatim: state.street)
                    .font(.headline)
                    .lineLimit(3)
                    .accessibilityIdentifier("watch.street")
                if let warning = state.warning {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Palette.warning)
                        Text(verbatim: warning)
                            .font(.footnote)
                            .foregroundStyle(Palette.warningText)
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.warning.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("watch.warning")
                }
                HStack {
                    Text(verbatim: state.arrivalLabel)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(verbatim: state.arrival)
                        .monospacedDigit()
                }
                .font(.footnote)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("watch.arrival")
                if let battery = state.battery {
                    Label {
                        Text(verbatim: battery)
                    } icon: {
                        Image(systemName: "battery.75percent")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("watch.battery")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var idle: some View {
        VStack(spacing: 6) {
            Image(systemName: "scooter")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(Palette.maneuver)
            Text(verbatim: "Naviscoot")
                .font(.headline)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("watch.idle")
    }
}

private enum Palette {
    static let maneuver = Color(red: 0x3B / 255, green: 0x82 / 255, blue: 0xF6 / 255)
    static let warning = Color(red: 0xF9 / 255, green: 0x73 / 255, blue: 0x16 / 255)
    static let warningText = Color(red: 0xFD / 255, green: 0xBA / 255, blue: 0x74 / 255)
}
