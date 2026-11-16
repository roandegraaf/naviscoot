import MapLibreSwiftUI
import SwiftUI

struct ScooterGlance: Equatable {
    enum Link: Equatable {
        case connected
        case connecting
        case offline
    }

    let percent: Int?
    let rangeKm: Int?
    let link: Link
    let status: String

    // Hidden until a scooter is set up; once it is, the strip stays and shows the last reading from this session.
    init?(state: ScooterConnection.State, telemetry: ScooterTelemetry?, configured: Bool, language: Language = .current) {
        guard configured || telemetry != nil else { return nil }
        switch state {
        case .connected:
            link = .connected
            status = Strings.tr("settings.scooter.status.connected", language: language)
        case .connecting:
            link = .connecting
            status = Strings.tr("settings.scooter.status.connecting", language: language)
        case .off, .failed:
            link = .offline
            status = Strings.tr("settings.scooter.status.notConnected", language: language)
        }
        percent = telemetry?.batteryPercent
        rangeKm = telemetry.map { Int(max(0, $0.rangeKm).rounded()) }
    }

    var battery: String? { percent.map { "\($0)%" } }

    var range: String? { rangeKm.map { "\($0) km" } }

    @MainActor
    init?(_ scooter: ScooterConnection) {
        self.init(state: scooter.state, telemetry: scooter.telemetry, configured: scooter.isConfigured)
    }

    var accessibilityValue: String {
        [battery, range, status].compactMap { $0 }.joined(separator: ", ")
    }

    var batterySymbol: String {
        guard let percent else { return "scooter" }
        switch percent {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}

struct ScooterStrip: View {
    let glance: ScooterGlance
    var floating = true
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 8) {
                Image(systemName: glance.batterySymbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                if let battery = glance.battery {
                    Text(verbatim: battery)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .monospacedDigit()
                }
                if let range = glance.range {
                    Text(verbatim: range)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                        .monospacedDigit()
                }
                if glance.battery == nil {
                    Text(glance.status)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                }
                Circle()
                    .fill(dotColor)
                    .frame(width: 9, height: 9)
            }
            .lineLimit(1)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .frame(maxWidth: floating ? nil : .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(StripBackground(floating: floating))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Strings.scooterSection)
        .accessibilityValue(glance.accessibilityValue)
        .accessibilityHint(Strings.scooterStripHint)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onOpen() }
        .accessibilityIdentifier("home.scooter")
    }

    private var dotColor: Color {
        switch glance.link {
        case .connected: Theme.connected
        case .connecting: Theme.unverified
        case .offline: Theme.muted
        }
    }
}

private struct StripBackground: ViewModifier {
    let floating: Bool

    func body(content: Content) -> some View {
        if !floating {
            content.background(Theme.iconBackground, in: RoundedRectangle(cornerRadius: 14))
        } else if #available(iOS 26, *) {
            content.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            content
                .background(.regularMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
        }
    }
}

// Fed from the map's realtime proxy so only the pin redraws while the map pans, not the whole home screen.
@MainActor
@Observable
final class MapPointTracker {
    private(set) var point: CGPoint?
    @ObservationIgnored private var proxy: MapViewProxy?
    @ObservationIgnored private var coordinate: Coordinate?

    func mapChanged(_ proxy: MapViewProxy) {
        self.proxy = proxy
        refresh()
    }

    func track(_ coordinate: Coordinate?) {
        self.coordinate = coordinate
        refresh()
    }

    private func refresh() {
        let next = coordinate.flatMap { coordinate in proxy.map { $0.convert(coordinate.clLocation, toPointTo: nil) } }
        if next != point { point = next }
    }
}

struct ParkedScooterPin: View {
    let parked: ParkedScooter
    let tracker: MapPointTracker
    @Binding var expanded: Bool
    let onWalk: () -> Void

    private let size: CGFloat = 40

    var body: some View {
        if let point = tracker.point {
            pin
                .overlay(alignment: .bottom) {
                    if expanded {
                        callout
                            .fixedSize()
                            .offset(y: -(size + 10))
                    }
                }
                .position(point)
        }
    }

    private var pin: some View {
        Button {
            withAnimation(.snappy) { expanded.toggle() }
        } label: {
            Image(systemName: "scooter")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(Theme.verified, in: Circle())
                .overlay(Circle().stroke(.white, lineWidth: 3))
                .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                .frame(width: 48, height: 48)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Strings.scooterParkedTitle)
        .accessibilityValue(parked.subtitle(now: Date()))
        .accessibilityIdentifier("home.parkedPin")
    }

    private var callout: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Strings.scooterParkedTitle)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    Text(parked.subtitle(now: context.date))
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.muted)
                }
            }
            Button(action: onWalk) {
                Label(Strings.walkThere, systemImage: "figure.walk")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 44)
                    .background(Theme.verified, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home.parkedPin.walk")
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.2), radius: 10, y: 3)
    }
}
