import Foundation

enum SearchSource: Equatable {
    case address(pdokId: String)
    case place
}

struct SearchResult: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let source: SearchSource
    let coordinate: Coordinate?
}

struct Destination: Equatable {
    let title: String
    let subtitle: String
    let coordinate: Coordinate
}

enum SearchMerge {
    static func merge(addresses: [SearchResult], places: [SearchResult], query: String, limit: Int = 12) -> [SearchResult] {
        let addressTitles = Set(addresses.map { normalized($0.title) })
        let uniquePlaces = places.filter { !addressTitles.contains(normalized($0.title)) }
        let (first, second) = looksLikeAddress(query) ? (addresses, uniquePlaces) : (uniquePlaces, addresses)

        var merged: [SearchResult] = []
        var seen = Set<String>()
        for index in 0 ..< max(first.count, second.count) {
            for list in [first, second] where index < list.count {
                let result = list[index]
                if seen.insert(result.id).inserted {
                    merged.append(result)
                }
            }
        }
        return Array(merged.prefix(limit))
    }

    static func looksLikeAddress(_ query: String) -> Bool {
        query.contains(where: \.isNumber)
    }

    static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "nl_NL"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
