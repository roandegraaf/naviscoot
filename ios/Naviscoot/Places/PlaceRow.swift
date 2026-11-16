import SwiftUI

struct PlaceRow: View {
    let systemImage: String
    let title: String
    let subtitle: String
    let id: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 44, height: 44)
                    .background(Theme.iconBackground, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.muted)
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

extension Place {
    var systemImage: String {
        switch kind {
        case .home: "house.fill"
        case .work: "briefcase.fill"
        case .favourite: "star.fill"
        case .recent: "clock.arrow.circlepath"
        }
    }

    var rowSubtitle: String { name == nil ? subtitle : address }
}
