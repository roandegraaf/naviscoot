import Foundation

@MainActor
final class SearchModel: ObservableObject {
    @Published var query = "" {
        didSet { scheduleSearch() }
    }

    @Published private(set) var results: [SearchResult] = []
    @Published private(set) var isSearching = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var resolvingId: String?

    var origin: () -> Coordinate? = { nil }
    private let pdok: PDOKClient
    private var searchTask: Task<Void, Never>?

    init(pdok: PDOKClient = PDOKClient()) {
        self.pdok = pdok
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2 else {
            results = []
            errorMessage = nil
            isSearching = false
            return
        }
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await self?.run(text)
        }
    }

    private func run(_ text: String) async {
        isSearching = true
        let near = origin()
        async let addresses = Self.attempt { try await self.pdok.suggest(text, near: near) }
        async let places = Self.attempt { try await PlaceSearch.search(text, near: near) }
        let (addressResult, placeResult) = await (addresses, places)
        guard !Task.isCancelled else { return }
        isSearching = false
        results = SearchMerge.merge(addresses: addressResult ?? [], places: placeResult ?? [], query: text)
        errorMessage = (addressResult == nil && placeResult == nil) ? Strings.searchFailed : nil
    }

    private static func attempt(_ work: () async throws -> [SearchResult]) async -> [SearchResult]? {
        try? await work()
    }

    func resolve(_ result: SearchResult) async -> Destination? {
        if let coordinate = result.coordinate {
            return Destination(title: result.title, subtitle: result.subtitle, coordinate: coordinate)
        }
        guard case let .address(pdokId) = result.source else { return nil }
        resolvingId = result.id
        defer { resolvingId = nil }
        do {
            let coordinate = try await pdok.lookup(id: pdokId)
            return Destination(title: result.title, subtitle: result.subtitle, coordinate: coordinate)
        } catch {
            errorMessage = Strings.lookupFailed
            return nil
        }
    }
}
