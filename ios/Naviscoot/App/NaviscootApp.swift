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
    @State private var settings = AppSettings.shared
    @State private var places = PlacesStore.shared
    @State private var trips = TripStore.shared
    @State private var scooter = ScooterConnection.shared
    @State private var parked = ParkedScooterStore.shared
    @State private var pendingLinkLoss: Date?
    @StateObject private var location = LocationService()
    @StateObject private var search = SearchModel()
    @StateObject private var reports: ReportQueue
    @State private var destination: Destination?
    @State private var ride: RideModel?
    @State private var resume: ResumeModel?
    @State private var offeredRide: ActiveRide?
    @State private var launched = false
    private let client: NaviscootClient?
    private let rideStore = ActiveRideStore(url: ActiveRideStore.defaultURL)
    private let tripDrafts = TripDraftStore(url: TripDraftStore.defaultURL)

    init() {
        let client = APIConfig.fromBundle().map { NaviscootClient(config: $0) }
        self.client = client
        _reports = StateObject(wrappedValue: ReportQueue(sender: client, storeURL: ReportQueue.defaultStoreURL))
    }

    var body: some View {
        Group {
            if let ride {
                RideView(model: ride, location: location) {
                    self.ride = nil
                    self.destination = nil
                    search.query = ""
                }
            } else if let resume {
                ResumeView(model: resume) {
                    forgetActiveRide()
                    self.resume = nil
                }
            } else if let destination {
                PreviewView(destination: destination, client: client, settings: settings, location: location) {
                    self.destination = nil
                } onStart: { plan, setup in
                    startRide(plan: plan, setup: setup, resuming: false)
                }
            } else {
                SearchView(model: search, location: location, drawerEnabled: launched, resumeOffer: resumeOffer) { selected in
                    places.recordRecent(selected)
                    destination = selected
                }
            }
        }
        .environment(settings)
        .environment(places)
        .environment(trips)
        .environment(scooter)
        .onChange(of: scooter.telemetry?.batteryPercent) { _, percent in
            if let percent { ChargeNotifier.shared.observe(percent) }
        }
        .environment(parked)
        .onChange(of: ride == nil, initial: true) { _, idle in
            scooter.rideActive = !idle
            if idle { scooter.onTelemetry = nil }
            if idle, let lost = pendingLinkLoss, ParkingRule.recordsPendingLoss(lostAt: lost, rideEndedAt: Date()), let coordinate = location.coordinate {
                parked.record(coordinate, at: lost)
            }
            if idle { pendingLinkLoss = nil }
        }
        .onChange(of: scooter.state) { _, state in
            guard state == .connected else { return }
            parked.clear()
            pendingLinkLoss = nil
        }
        .onChange(of: settings.appearance, initial: true) { _, appearance in
            applyAppearance(appearance)
        }
        .environment(\.locale, settings.language.locale)
        .onChange(of: location.coordinate) { _, coordinate in
            resume?.locationChanged(coordinate)
        }
        .onAppear {
            #if DEBUG
            HomeSeed.applyIfRequested(places: places, trips: trips)
            #endif
            search.origin = { [weak location] in location?.coordinate }
            location.start()
            scooter.onLinkLost = { [scooter, parked, location] lostAt in
                if ParkingRule.recordsLoss(rideActive: scooter.rideActive) {
                    if let coordinate = location.coordinate { parked.record(coordinate, at: lostAt) }
                } else {
                    pendingLinkLoss = lostAt
                }
            }
            #if !targetEnvironment(simulator)
            ScooterPrefill.apply(info: Bundle.main.infoDictionary, settings: settings, keychain: ScooterKeychain())
            #endif
            scooter.start()
            PhoneWatchLink.shared.activate()
            Task { await reports.flush() }
            if RideOptions.current.discardActiveRide {
                rideStore.clear()
                tripDrafts.clear()
            }
            if ride == nil, resume == nil {
                offeredRide = rideStore.load()
                if offeredRide == nil {
                    recordUnfinishedTrip()
                    RideLiveActivity.endAll()
                    PhoneWatchLink.shared.clear()
                }
            }
            launched = true
        }
    }

    // A window override (not preferredColorScheme) so sheets, alerts and dialogs follow, and "System" really returns to the OS setting.
    private func applyAppearance(_ appearance: AppearanceChoice) {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                window.overrideUserInterfaceStyle = appearance.interfaceStyle
            }
        }
    }

    private func forgetActiveRide() {
        rideStore.clear()
        recordUnfinishedTrip()
        RideLiveActivity.endAll()
        PhoneWatchLink.shared.clear()
    }

    private func recordUnfinishedTrip() {
        guard let draft = tripDrafts.load() else { return }
        tripDrafts.clear()
        trips.add(draft)
    }

    private var resumeOffer: ResumeOfferAlert {
        ResumeOfferAlert(offered: $offeredRide, onResume: beginResume, onDiscard: forgetActiveRide)
    }

    private func beginResume(_ saved: ActiveRide) {
        guard let client else { return }
        let model = ResumeModel(ride: saved, planner: client)
        model.onPlanned = { plan in
            startRide(plan: plan, setup: saved, resuming: true)
            resume = nil
        }
        resume = model
        model.locationChanged(location.coordinate)
    }

    private func startRide(plan: RoutePlan, setup: ActiveRide, resuming: Bool) {
        guard let client else { return }
        let record: (TripDraft) -> Void = { [trips] draft in trips.add(draft) }
        let saved = resuming ? tripDrafts.load() : nil
        let trip = saved.map { TripRecorder.resuming($0, drafts: tripDrafts, onFinish: record) }
            ?? TripRecorder(draft: TripDraft(startedAt: Date(), destination: setup.destination.title), drafts: tripDrafts, onFinish: record)
        if let telemetry = scooter.telemetry, let at = scooter.telemetryAt, Date().timeIntervalSince(at) < 120 {
            trip.scooterSample(telemetry)
        }
        scooter.onTelemetry = { [weak trip] telemetry in trip?.scooterSample(telemetry) }
        let model = RideModel(
            plan: plan,
            ride: setup,
            planner: client,
            reports: reports,
            store: rideStore,
            options: .current,
            trip: trip,
            activity: RideLiveActivity(),
            watch: PhoneWatchLink.shared,
            scooterStatus: { [scooter, trips] in
                ScooterRideStatus.current(
                    telemetry: scooter.telemetry,
                    readAt: scooter.telemetryAt,
                    connected: scooter.state == .connected,
                    now: Date(),
                    model: trips.consumption
                )
            }
        )
        ride = model
        model.start()
    }
}

// Attached to the home drawer rather than the root: the drawer is a presented sheet, and an alert from the root would not show over it.
struct ResumeOfferAlert: ViewModifier {
    @Binding var offered: ActiveRide?
    let onResume: (ActiveRide) -> Void
    let onDiscard: () -> Void

    func body(content: Content) -> some View {
        content.alert(Strings.resumeTitle, isPresented: Binding(get: { offered != nil }, set: { if !$0 { offered = nil } }), presenting: offered) { saved in
            Button(Strings.resumeRide) { onResume(saved) }
                .accessibilityIdentifier("resume.offer.resume")
            Button(Strings.endRideConfirm, role: .cancel) {
                onDiscard()
            }
                .accessibilityIdentifier("resume.offer.discard")
        } message: { saved in
            Text(Strings.resumeMessage(saved))
        }
    }
}
