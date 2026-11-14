import SwiftUI

@main
struct NaviscootApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

struct RootView: View {
    @StateObject private var location = LocationService()
    @StateObject private var search = SearchModel()
    @State private var destination: Destination?
    private let client = APIConfig.fromBundle().map { NaviscootClient(config: $0) }

    var body: some View {
        Group {
            if let destination {
                PreviewView(destination: destination, client: client, location: location) {
                    self.destination = nil
                }
            } else {
                SearchView(model: search, location: location) { selected in
                    destination = selected
                }
            }
        }
        .preferredColorScheme(.light)
        .onAppear {
            search.origin = { [weak location] in location?.coordinate }
            location.start()
        }
    }
}
