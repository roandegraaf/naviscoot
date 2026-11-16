import SwiftUI

struct SearchResultRow: View {
    let result: SearchResult
    let isResolving: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: result.source == .place ? "building.2" : "mappin.and.ellipse")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 44, height: 44)
                    .background(Theme.iconBackground, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text(subtitle)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.muted)
                }
                .lineLimit(1)
                Spacer(minLength: 0)
                if isResolving {
                    ProgressView()
                }
            }
            .frame(minHeight: 68)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("search.result")
    }

    private var subtitle: String {
        let kind = result.source == .place ? Strings.placeKind : Strings.addressKind
        return result.subtitle.isEmpty ? kind : "\(kind) · \(result.subtitle)"
    }
}
