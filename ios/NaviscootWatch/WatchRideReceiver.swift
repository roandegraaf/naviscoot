import Foundation
import WatchConnectivity
import WatchKit

@MainActor
final class WatchRideReceiver: NSObject, ObservableObject {
    @Published private(set) var message: WatchRideMessage?

    private var inbox = WatchInbox()

    // A background launch to deliver a context shows no view, so activation can't wait for onAppear.
    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    private func receive(_ payload: [String: Any]) {
        guard let incoming = WatchRideMessage(payload: payload) else { return }
        let haptic = inbox.receive(incoming, now: Date())
        message = inbox.latest
        if let haptic {
            WKInterfaceDevice.current().play(Self.feedback(for: haptic))
        }
    }

    static func feedback(for haptic: WatchHaptic) -> WKHapticType {
        switch haptic {
        case .turn: .notification
        case .unverified: .failure
        case .arrived: .success
        }
    }
}

extension WatchRideReceiver: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith _: WCSessionActivationState, error _: Error?) {
        let context = session.receivedApplicationContext
        Task { @MainActor in self.receive(context) }
    }

    nonisolated func session(_: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.receive(applicationContext) }
    }

    nonisolated func session(_: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in self.receive(message) }
    }
}
