import SwiftUI

@main
struct NaviscootWatchApp: App {
    @StateObject private var receiver = WatchRideReceiver()

    var body: some Scene {
        WindowGroup {
            WatchRideView(message: receiver.message)
        }
    }
}
