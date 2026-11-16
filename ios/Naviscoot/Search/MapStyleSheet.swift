import SwiftUI

struct MapStyleSheet: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(Strings.mapStyleSection)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button(Strings.done) { dismiss() }
                    .font(.system(size: 18, weight: .semibold))
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("layers.done")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(MapStyle.allCases) { style in
                        card(style)
                    }
                }
                .padding(.vertical, 2)
            }
            Text(Strings.mapStyleFooter)
                .font(.system(size: 14))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .presentationDetents([.height(300)])
        .presentationDragIndicator(.visible)
    }

    private func card(_ style: MapStyle) -> some View {
        let selected = settings.mapStyle == style
        return Button {
            settings.mapStyle = style
        } label: {
            VStack(spacing: 8) {
                MapStyleSwatch(style: style)
                    .frame(width: 104, height: 76)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(selected ? Theme.verified : Theme.line, lineWidth: selected ? 3 : 1)
                    }
                Text(Strings.mapStyleName(style))
                    .font(.system(size: 15, weight: selected ? .bold : .medium))
                    .foregroundStyle(selected ? Theme.verifiedText : Theme.ink)
                    .lineLimit(1)
            }
            .frame(width: 108)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Strings.mapStyleName(style))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("layers.style.\(style.rawValue)")
    }
}

private struct MapStyleSwatch: View {
    let style: MapStyle

    var body: some View {
        let colors = style.swatchColors
        ZStack {
            colors.land
            Circle()
                .fill(colors.water)
                .frame(width: 70, height: 70)
                .offset(x: 38, y: 30)
            Capsule()
                .fill(colors.road)
                .frame(width: 140, height: 7)
                .rotationEffect(.degrees(-28))
            Capsule()
                .fill(colors.minorRoad)
                .frame(width: 6, height: 90)
                .offset(x: -26)
        }
        .accessibilityHidden(true)
    }
}

private extension MapStyle {
    var swatchColors: (land: Color, water: Color, road: Color, minorRoad: Color) {
        switch self {
        case .liberty: (Color(hex: 0xF3EEE6), Color(hex: 0xA6CBEB), Color(hex: 0xF6C77A), .white)
        case .bright: (Color(hex: 0xF8F4F0), Color(hex: 0x9DCBF0), Color(hex: 0xFFD966), .white)
        case .positron: (Color(hex: 0xF2F3F0), Color(hex: 0xC6CED2), Color(hex: 0xFFFFFF), Color(hex: 0xE2E4E2))
        case .dark: (Color(hex: 0x1D2430), Color(hex: 0x0E2538), Color(hex: 0x5A6475), Color(hex: 0x394252))
        case .fiord: (Color(hex: 0x45516E), Color(hex: 0x38435C), Color(hex: 0x6E7FA3), Color(hex: 0x56637F))
        }
    }
}
