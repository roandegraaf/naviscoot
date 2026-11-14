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
    @StateObject private var reports: ReportQueue
    @State private var destination: Destination?
    @State private var ride: RideModel?
    private let client: NaviscootClient?

    init() {
        let client = APIConfig.fromBundle().map { NaviscootClient(config: $0) }
        self.client = client
        _reports = StateObject(wrappedValue: ReportQueue(sender: client, storeURL: ReportQueue.defaultStoreURL))
    }

    var body: some View {
        Group {
            if let ride {
                RideView(model: ride) {
                    self.ride = nil
                    self.destination = nil
                }
            } else if let destination {
                PreviewView(destination: destination, client: client, location: location) {
                    self.destination = nil
                } onStart: { plan, verifiedOnly in
                    guard let client else { return }
                    let model = RideModel(
                        plan: plan,
                        destination: destination,
                        verifiedOnly: verifiedOnly,
                        planner: client,
                        reports: reports,
                        options: .current
                    )
                    ride = model
                    model.start()
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
            Task { await reports.flush() }
        }
    }
}
