import FerrostarCoreFFI
import MapLibreSwiftDSL
import MapLibreSwiftUI
import SwiftUI

struct RideView: View {
    @ObservedObject var model: RideModel
    let onEnd: () -> Void
    @State private var camera: MapViewCamera

    init(model: RideModel, onEnd: @escaping () -> Void) {
        self.model = model
        self.onEnd = onEnd
        let start = model.plan.route.geometry.first.map(Coordinate.init) ?? model.destination.coordinate
        _camera = State(initialValue: .center(start.clLocation, zoom: 16.5, pitch: 40))
    }

    var body: some View {
        ZStack(alignment: .top) {
            RouteMapView(
                camera: $camera,
                segments: model.plan.segments,
                destination: model.destination.coordinate,
                user: model.userCoordinate
            )
            .mapControls {
                LogoView()
                AttributionButton()
            }

            VStack(alignment: .leading, spacing: 8) {
                bannerView
                chips
                if model.options.simulate {
                    simulationPanel
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            HStack {
                Spacer()
                VStack(spacing: 12) {
                    roundButton(symbol: "flag", tint: Theme.unverifiedText, label: Strings.report, id: "ride.report", action: model.report)
                    roundButton(
                        symbol: model.isMuted ? "speaker.slash" : "speaker.wave.2",
                        tint: Theme.ink,
                        label: model.isMuted ? Strings.unmute : Strings.mute,
                        id: "ride.mute",
                        action: model.toggleMute
                    )
                }
                .padding(.trailing, 12)
            }
            .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 10) {
                Spacer()
                if let status = model.reportStatus {
                    reportToast(status)
                }
                HStack(alignment: .bottom, spacing: 10) {
                    speedView
                    if let limit = model.limitKmh {
                        limitSign(limit)
                    }
                }
                .padding(.horizontal, 12)
                if let alert = model.alert {
                    warning(alert)
                        .padding(.horizontal, 12)
                }
                rideBar
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .onChange(of: model.userCoordinate) { _, coordinate in
            guard let coordinate else { return }
            camera = .center(coordinate.clLocation, zoom: 16.5, pitch: 40, direction: model.courseDegrees)
        }
    }

    @ViewBuilder
    private var bannerView: some View {
        HStack(spacing: 16) {
            Image(systemName: Self.symbol(for: model.banner, arrived: model.arrived))
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                if model.arrived {
                    Text(Strings.arrived)
                        .font(.system(size: 30, weight: .heavy))
                        .foregroundStyle(.white)
                        .accessibilityIdentifier("ride.banner.street")
                } else if let banner = model.banner {
                    Text(Format.approximateDistance(meters: banner.distanceM))
                        .font(.system(size: 46, weight: .heavy))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                        .accessibilityIdentifier("ride.banner.distance")
                    Text(banner.text)
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(Color(hex: 0xE5E7EB))
                        .lineLimit(2)
                        .accessibilityIdentifier("ride.banner.street")
                } else {
                    Text(Strings.startingGuidance)
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(Color(hex: 0xE5E7EB))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(Theme.ink, in: RoundedRectangle(cornerRadius: 22))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ride.banner")
    }

    private var chips: some View {
        HStack(spacing: 8) {
            if let stretchClass = model.currentClass {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Theme.barColor(for: stretchClass))
                        .frame(width: 10, height: 10)
                    Text(Strings.chip(for: stretchClass, limit: model.limitKmh))
                }
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.labelColor(for: stretchClass))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.white, in: RoundedRectangle(cornerRadius: 14))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("ride.stretch")
            }
            if model.isRerouting {
                Text(Strings.rerouting)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Theme.danger, in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityIdentifier("ride.rerouting")
            }
        }
    }

    private var simulationPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("\(Strings.simulatedRide), \(Strings.reroutes(model.rerouteCount))")
                    .accessibilityIdentifier("sim.status")
                Button(Strings.simulateDetour, action: model.simulateDetour)
                    .font(.system(size: 13, weight: .bold))
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("sim.detour")
            }
            Text(model.routeId)
                .font(.system(size: 10, design: .monospaced))
                .accessibilityIdentifier("sim.routeId")
            Text(model.spoken.last.map { "\($0.language ?? "?"): \($0.text)" } ?? "")
                .lineLimit(2)
                .accessibilityIdentifier("sim.spoken")
                .accessibilityValue(model.spoken.map { "\($0.language ?? "?")|\($0.text)" }.joined(separator: "\n"))
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(Theme.muted)
        .padding(8)
        .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 12))
    }

    private var speedView: some View {
        VStack(spacing: 0) {
            Text(model.speedKmh.map(String.init) ?? "–")
                .font(.system(size: 44, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
            Text(Strings.kmh)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.muted)
        }
        .frame(width: 104, height: 104)
        .background(.white, in: Circle())
        .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("ride.speed")
    }

    private func limitSign(_ limit: Int) -> some View {
        Text("\(limit)")
            .font(.system(size: 28, weight: .heavy))
            .foregroundStyle(Theme.ink)
            .frame(width: 64, height: 64)
            .background(.white, in: Circle())
            .overlay(Circle().stroke(Color(hex: 0xDC2626), lineWidth: 7))
            .accessibilityLabel(Strings.speedLimit(limit))
            .accessibilityIdentifier("ride.limit")
    }

    private func warning(_ alert: UnverifiedAlert) -> some View {
        let text = switch alert {
        case let .ahead(_, distanceM, lengthM):
            Strings.unverifiedAhead(Format.approximateDistance(meters: distanceM), length: Format.distance(meters: lengthM))
        case let .inside(_, remainingM):
            Strings.unverifiedInside(Format.approximateDistance(meters: remainingM))
        }
        return HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 22, weight: .bold))
                .accessibilityHidden(true)
            Text(text)
        }
        .font(.system(size: 16, weight: .bold))
        .foregroundStyle(Theme.unverifiedText)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0xFFF1E7), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.unverified, lineWidth: 2))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("ride.warning")
    }

    private func reportToast(_ status: RideModel.ReportStatus) -> some View {
        let text = switch status {
        case .sending: Strings.reportSending
        case .sent: Strings.reportSent
        case let .queued(pending): Strings.reportQueued(pending)
        case .rejected: Strings.reportRejected
        }
        return Text(text)
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Theme.ink.opacity(0.92), in: Capsule())
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("ride.reportStatus")
    }

    private var rideBar: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.remainingS.map { Format.duration(seconds: $0) } ?? "–")
                    .font(.system(size: 30, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                Text(remainingSubtitle)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.muted)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("ride.remaining")
            Spacer()
            Button {
                model.end()
                onEnd()
            } label: {
                Text(Strings.end)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 26)
                    .frame(minHeight: 56)
                    .background(Theme.danger, in: Capsule())
            }
            .accessibilityIdentifier("ride.end")
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 34)
        .background(.white, in: UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24))
        .shadow(color: .black.opacity(0.12), radius: 12, y: -2)
    }

    private var remainingSubtitle: String {
        guard let meters = model.remainingM, let seconds = model.remainingS else { return " " }
        let arrival = Format.clockTime(Date().addingTimeInterval(seconds))
        return "\(Format.distance(meters: Int(meters.rounded()))), \(Strings.arrive(arrival))"
    }

    private func roundButton(symbol: String, tint: Color, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 64, height: 64)
                .background(.white, in: Circle())
                .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
        }
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    static func symbol(for banner: RideModel.Banner?, arrived: Bool) -> String {
        if arrived { return "flag.checkered" }
        guard let banner else { return "location.north.line" }
        switch banner.maneuverType {
        case .arrive: return "flag.checkered"
        case .roundabout, .rotary, .roundaboutTurn, .exitRoundabout, .exitRotary:
            return "arrow.triangle.turn.up.right.circle"
        default: break
        }
        switch banner.maneuverModifier {
        case .uTurn: return "arrow.uturn.down"
        case .sharpRight, .right: return "arrow.turn.up.right"
        case .slightRight: return "arrow.up.right"
        case .sharpLeft, .left: return "arrow.turn.up.left"
        case .slightLeft: return "arrow.up.left"
        case .straight, .none: return "arrow.up"
        }
    }
}
