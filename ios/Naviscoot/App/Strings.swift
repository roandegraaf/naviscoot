import Foundation

enum Strings {
    static func tr(_ key: String, language: Language = .current) -> String {
        language.bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    static func format(_ key: String, _ arguments: CVarArg..., language: Language = .current) -> String {
        String(format: tr(key, language: language), locale: language.locale, arguments: arguments)
    }

    static var searchPlaceholder: String { tr("search.placeholder") }
    static var searchFailed: String { tr("search.failed") }
    static var lookupFailed: String { tr("search.lookupFailed") }
    static var noResults: String { tr("search.noResults") }
    static var addressKind: String { tr("search.kind.address") }
    static var placeKind: String { tr("search.kind.place") }
    static var clear: String { tr("search.clear") }
    static var closeSearch: String { tr("search.close") }
    static var expandRouteDetails: String { tr("preview.sheet.expand") }
    static var collapseRouteDetails: String { tr("preview.sheet.collapse") }
    static var openSettings: String { tr("search.settings") }
    static var showMyLocation: String { tr("home.locate") }
    static var recentTrips: String { tr("home.recentTrips") }
    static var seeAll: String { tr("home.seeAll") }
    static var seeAllTrips: String { tr("home.seeAll.trips") }
    static var scooterStripHint: String { tr("home.scooter.hint") }
    static var walkThere: String { tr("home.parked.walk") }
    static var tripHistory: String { tr("trips.title") }
    static var noTrips: String { tr("trips.empty") }
    static var noTripsFooter: String { tr("trips.empty.footer") }
    static var tripTotals: String { tr("trips.totals") }
    static var tripCount: String { tr("trips.total.count") }
    static var tripDistance: String { tr("trips.total.distance") }
    static var tripTime: String { tr("trips.total.time") }
    static var tripSpeed: String { tr("trips.total.speed") }
    static var tripsSection: String { tr("trips.section") }
    static var deleteTrip: String { tr("trips.delete") }
    static var trip: String { tr("trip.title") }
    static var tripDuration: String { tr("trip.duration") }
    static var tripMap: String { tr("trip.map") }
    static func tripVia(_ stops: [String]) -> String { format("trip.via", stops.joined(separator: ", ")) }
    static var home: String { tr("places.home") }
    static var work: String { tr("places.work") }
    static var setHome: String { tr("places.setHome") }
    static var setWork: String { tr("places.setWork") }
    static var savedPlaces: String { tr("places.saved") }
    static var favourites: String { tr("places.favourites") }
    static var recents: String { tr("places.recents") }
    static var clearRecents: String { tr("places.clearRecents") }
    static var clearRecentsAccessibility: String { tr("places.clearRecents.accessibility") }
    static var editPlaces: String { tr("places.edit") }
    static var editPlacesTitle: String { tr("places.edit.title") }
    static var nothingSaved: String { tr("places.edit.empty") }
    static var rename: String { tr("places.rename") }
    static var renameTitle: String { tr("places.rename.title") }
    static var removePlace: String { tr("places.remove") }
    static var save: String { tr("common.save") }
    static var savePlace: String { tr("preview.save") }
    static var savedPlace: String { tr("preview.saved") }
    static var saveAsFavourite: String { tr("preview.save.favourite") }
    static var saveAsHome: String { tr("preview.save.home") }
    static var saveAsWork: String { tr("preview.save.work") }
    static var droppedPin: String { tr("pin.dropped") }
    static var lookingUpAddress: String { tr("pin.lookingUp") }
    static var routeHere: String { tr("pin.route") }
    static var removePin: String { tr("pin.remove") }

    static func slotName(_ kind: PlaceKind) -> String {
        switch kind {
        case .home: home
        case .work: work
        case .favourite: favourites
        case .recent: recents
        }
    }

    static func setSlot(_ kind: PlaceKind) -> String {
        kind == .work ? setWork : setHome
    }

    static var back: String { tr("preview.back") }
    static var to: String { tr("preview.to") }
    static var waitingForLocation: String { tr("preview.waitingForLocation") }
    static var locationDenied: String { tr("preview.locationDenied") }
    static var calculating: String { tr("preview.calculating") }
    static var retry: String { tr("preview.retry") }
    static var carriageway: String { tr("class.carriageway") }
    static var mopedPath: String { tr("class.mopedPath") }
    static var unverified: String { tr("class.unverified") }
    static var forbidden: String { tr("class.forbidden") }
    static var verifiedOnly: String { tr("preview.verifiedOnly") }
    static var verifiedOnlyNothingToSkip: String { tr("preview.verifiedOnly.nothingToSkip") }
    static var verifiedOnlyActive: String { tr("preview.verifiedOnly.active") }
    static var start: String { tr("preview.start") }
    static var showOnMap: String { tr("preview.showOnMap") }
    static var apiNotConfigured: String { tr("error.apiNotConfigured") }
    static var unauthorized: String { tr("error.unauthorized") }
    static var noRoute: String { tr("error.noRoute") }
    static var serviceUnavailable: String { tr("error.serviceUnavailable") }
    static var classificationFailed: String { tr("error.classificationFailed") }
    static var routeParseFailed: String { tr("error.routeParseFailed") }
    static var networkFailed: String { tr("error.network") }
    static var conflictingTimes: String { tr("error.conflictingTimes") }
    static var alternativesNeedTwoPoints: String { tr("error.alternativesNeedTwoPoints") }
    static var from: String { tr("preview.from") }
    static var yourLocation: String { tr("preview.yourLocation") }
    static var useYourLocation: String { tr("preview.useYourLocation") }
    static var changeStart: String { tr("preview.changeStart") }
    static var addStop: String { tr("preview.addStop") }
    static var moveStopUp: String { tr("preview.moveStopUp") }
    static var moveStopDown: String { tr("preview.moveStopDown") }
    static var removeStop: String { tr("preview.removeStop") }
    static var startSearchTitle: String { tr("preview.startSearchTitle") }
    static var stopSearchTitle: String { tr("preview.stopSearchTitle") }
    static var leaveNow: String { tr("preview.time.now") }
    static var routeNoUnverified: String { tr("preview.route.noUnverified") }
    static var startFromYourLocation: String { tr("preview.startFromYourLocation") }
    static var timeTitle: String { tr("time.title") }
    static var cancel: String { tr("common.cancel") }

    static var end: String { tr("ride.end") }
    static var report: String { tr("ride.report") }
    static var reportSending: String { tr("ride.report.sending") }
    static var reportSent: String { tr("ride.report.sent") }
    static var reportRejected: String { tr("ride.report.rejected") }
    static var mute: String { tr("ride.mute") }
    static var unmute: String { tr("ride.unmute") }
    static var rerouting: String { tr("ride.rerouting") }
    static var arrived: String { tr("ride.arrived") }
    static var kmh: String { tr("ride.kmh") }
    static var startingGuidance: String { tr("ride.startingGuidance") }
    static var simulatedRide: String { tr("ride.sim.title") }
    static var simulateDetour: String { tr("ride.sim.detour") }
    static var endRideTitle: String { tr("ride.endConfirm.title") }
    static var endRideConfirm: String { tr("ride.endConfirm.end") }
    static var keepRiding: String { tr("ride.endConfirm.keep") }
    static var rerouteFailed: String { tr("ride.rerouteFailed") }
    static var editRoute: String { tr("ride.edit") }
    static var addStopMidRide: String { tr("ride.edit.addStop") }
    static var changeDestination: String { tr("ride.edit.changeDestination") }
    static var planningNewRoute: String { tr("ride.edit.planning") }
    static var routeOverview: String { tr("ride.overview") }
    static var recenter: String { tr("ride.recenter") }
    static var locationAccessOff: String { tr("ride.location.denied") }
    static var preciseLocationOff: String { tr("ride.location.reduced") }
    static var locationSettings: String { tr("ride.location.settings") }
    static var resumeTitle: String { tr("resume.title") }
    static var resumeHeading: String { tr("resume.heading") }
    static var resumeRide: String { tr("resume.resume") }
    static var resumePlanning: String { tr("resume.planning") }
    static var chipCarriageway: String { tr("chip.carriageway") }
    static var chipMopedPath: String { tr("chip.mopedPath") }
    static var chipUnverified: String { tr("chip.unverified") }
    static var chipForbidden: String { tr("chip.forbidden") }

    static var settingsTitle: String { tr("settings.title") }
    static var done: String { tr("settings.done") }
    static var languageSection: String { tr("settings.language") }
    static var languageFooter: String { tr("settings.language.footer") }
    static var routeSection: String { tr("settings.route") }
    static var verifiedOnlyDefault: String { tr("settings.verifiedOnlyDefault") }
    static var verifiedOnlyDefaultFooter: String { tr("settings.verifiedOnlyDefault.footer") }
    static var aboutSection: String { tr("settings.about") }
    static var version: String { tr("settings.version") }
    static var avoidSection: String { tr("settings.avoid") }
    static var avoidFerries: String { tr("settings.avoid.ferries") }
    static var avoidUnpaved: String { tr("settings.avoid.unpaved") }
    static var avoidMainRoads: String { tr("settings.avoid.mainRoads") }
    static var avoidFooter: String { tr("settings.avoid.footer") }
    static var appearanceSection: String { tr("settings.appearance") }
    static var mapStyleSection: String { tr("settings.mapStyle") }
    static var mapStyleFooter: String { tr("settings.mapStyle.footer") }
    static var mapSection: String { tr("settings.map") }
    static var mapFooter: String { tr("settings.map.footer") }
    static var darkMapAtNight: String { tr("settings.darkMapAtNight") }
    static var northUp: String { tr("settings.northUp") }
    static var threeD: String { tr("settings.threeD") }
    static var autoZoom: String { tr("settings.autoZoom") }
    static var voiceSection: String { tr("settings.voiceSection") }
    static var voiceFooter: String { tr("settings.voiceSection.footer") }
    static var voice: String { tr("settings.voice") }
    static var speedingSection: String { tr("settings.speeding") }
    static var speedingFooter: String { tr("settings.speeding.footer") }
    static var speedingAlert: String { tr("settings.speeding.alert") }
    static var overSpeedLimit: String { tr("ride.speeding") }
    static func speechRate(_ percent: Int) -> String { format("settings.speechRate", percent) }
    static func speechVolume(_ percent: Int) -> String { format("settings.speechVolume", percent) }
    static func speedingTolerance(_ kmh: Int) -> String { format("settings.speeding.tolerance", kmh) }
    static func rangeFits(_ spare: String) -> String { format("range.fits", spare) }
    static func rangeTight(_ spare: String) -> String { format("range.tight", spare) }
    static func rangeShort(_ missing: String) -> String { format("range.short", missing) }
    static var rangeRoundTripFits: String { tr("range.roundTrip.fits") }
    static var rangeRoundTripTight: String { tr("range.roundTrip.tight") }
    static var rangeRoundTripShort: String { tr("range.roundTrip.short") }
    static func rangeBattery(_ percent: Int, _ range: String, _ source: String) -> String { format("range.battery", percent, range, source) }
    static var rangeSourceLearned: String { tr("range.source.learned") }
    static var rangeSourceSegway: String { tr("range.source.segway") }
    static func rangeReadAgo(_ duration: String) -> String { format("range.readAgo", duration) }
    static func rangeMargin(_ percent: Int) -> String { format("range.margin", percent) }
    static var rangePerPercent: String { tr("range.perPercent") }
    static var scooterSection: String { tr("settings.scooter") }
    static var turnBackWarning: String { tr("scooter.ride.turnBackSetting") }
    static var scooterParkedTitle: String { tr("scooter.parked.title") }
    static func scooterRideBattery(_ percent: Int, _ range: String, language: Language = .current) -> String {
        format("scooter.ride.battery", percent, range, language: language)
    }
    static var scooterFooter: String { tr("settings.scooter.footer") }
    static var scooterSerial: String { tr("settings.scooter.serial") }
    static var scooterPassword: String { tr("settings.scooter.password") }
    static var scooterPasswordSaved: String { tr("settings.scooter.passwordSaved") }
    static var scooterPasswordInvalid: String { tr("settings.scooter.passwordInvalid") }
    static var scooterRead: String { tr("settings.scooter.read") }
    static var scooterReading: String { tr("settings.scooter.reading") }
    static var scooterBattery: String { tr("settings.scooter.battery") }
    static var scooterRange: String { tr("settings.scooter.range") }
    static var scooterOdometer: String { tr("settings.scooter.odometer") }

    static var scooterStatusNotSetUp: String { tr("settings.scooter.status.notSetUp") }
    static var scooterStatusConnecting: String { tr("settings.scooter.status.connecting") }
    static var scooterStatusConnected: String { tr("settings.scooter.status.connected") }
    static var scooterStatusNotConnected: String { tr("settings.scooter.status.notConnected") }
    static var scooterConnection: String { tr("scooter.settings.connection") }
    static var scooterIdent: String { tr("scooter.settings.ident") }
    static var scooterIdentSaved: String { tr("scooter.settings.identSaved") }
    static var scooterIdentInvalid: String { tr("scooter.settings.identInvalid") }
    static var scooterRangeSection: String { tr("scooter.settings.range") }
    static var scooterBatterySection: String { tr("scooter.settings.battery") }
    static var scooterVoltage: String { tr("scooter.settings.voltage") }
    static var scooterCharge: String { tr("scooter.settings.charge") }
    static var scooterCycles: String { tr("scooter.settings.cycles") }
    static var scooterCurrent: String { tr("scooter.settings.current") }
    static var scooterCapacity: String { tr("scooter.settings.capacity") }
    static func scooterCapacityValue(_ remaining: String, _ full: String) -> String { format("scooter.settings.capacityValue", remaining, full) }
    static var scooterHealth: String { tr("scooter.settings.health") }
    static var scooterChargeCount: String { tr("scooter.settings.chargeCount") }
    static var scooterTemperature: String { tr("scooter.settings.temperature") }
    static var scooterCells: String { tr("scooter.settings.cells") }
    static func scooterCellsValue(_ count: Int, _ low: Int, _ high: Int, _ spread: Int) -> String {
        format("scooter.settings.cellsValue", count, low, high, spread)
    }
    static var scooterPackSerial: String { tr("scooter.settings.packSerial") }
    static var scooterFirmware: String { tr("scooter.settings.firmware") }
    static var scooterManufactured: String { tr("scooter.settings.manufactured") }
    static func scooterChargingCurrent(_ amps: String) -> String { format("scooter.settings.chargingCurrent", amps) }
    static var scooterNotAvailable: String { tr("scooter.settings.notAvailable") }
    static var scooterNotCharging: String { tr("scooter.settings.notCharging") }
    static var scooterCharging: String { tr("scooter.settings.charging") }
    static func scooterChargingRate(_ rate: String) -> String { format("scooter.settings.chargingRate", rate) }
    static func scooterChargingEta(_ target: Int, _ time: String) -> String { format("scooter.settings.chargingEta", target, time) }
    static var scooterBatteryFooter: String { tr("scooter.settings.batteryFooter") }
    static var scooterNotify: String { tr("scooter.settings.notify") }
    static var scooterNotifyTarget: String { tr("scooter.settings.notifyTarget") }
    static var scooterNotifyDenied: String { tr("scooter.settings.notifyDenied") }
    static var scooterNotifyFooter: String { tr("scooter.settings.notifyFooter") }
    static var scooterChargedTitle: String { tr("scooter.settings.chargedTitle") }
    static func scooterChargedBody(_ percent: Int) -> String { format("scooter.settings.chargedBody", percent) }
    static var scooterControls: String { tr("scooter.settings.controls") }
    static var scooterOpenSeat: String { tr("scooter.settings.openSeat") }
    static var scooterPowerOn: String { tr("scooter.settings.powerOn") }
    static var scooterPowerOff: String { tr("scooter.settings.powerOff") }
    static var scooterPowerOffConfirm: String { tr("scooter.settings.powerOffConfirm") }
    static var scooterControlsFooter: String { tr("scooter.settings.controlsFooter") }
    static var scooterRidingBlocked: String { tr("scooter.settings.ridingBlocked") }
    static var scooterSpeed: String { tr("scooter.settings.speed") }
    static var scooterSpeedCurrent: String { tr("scooter.settings.speedCurrent") }
    static var scooterSpeedNew: String { tr("scooter.settings.speedNew") }
    static var scooterSpeedApply: String { tr("scooter.settings.speedApply") }
    static var scooterSpeedUnreadable: String { tr("scooter.settings.speedUnreadable") }
    static func scooterSpeedRestore(_ limit: String) -> String { format("scooter.settings.speedRestore", limit) }
    static func scooterSpeedFooter(_ ratedKmh: Int) -> String { format("scooter.settings.speedFooter", ratedKmh) }

    static func scooterSpeedLimit(_ kmh: Int) -> String {
        kmh == 0 ? tr("scooter.settings.speedOff") : format("scooter.settings.speedValue", kmh)
    }

    static func scooterSpeedWrite(_ result: SpeedLimitWrite) -> String {
        switch result {
        case let .confirmed(kmh): format("scooter.settings.speedConfirmed", scooterSpeedLimit(kmh))
        case let .mismatch(kmh): format("scooter.settings.speedMismatch", scooterSpeedLimit(kmh))
        case .unreadable: tr("scooter.settings.speedUnreadable")
        }
    }

    static var scooterTopSpeed: String { tr("scooter.settings.topSpeed") }
    static var scooterTopSpeedCurrent: String { tr("scooter.settings.topSpeedCurrent") }
    static var scooterTopSpeedUnlock: String { tr("scooter.settings.topSpeedUnlock") }
    static var scooterTopSpeedFooter: String { tr("scooter.settings.topSpeedFooter") }

    static func scooterTopSpeedState(_ state: TopSpeedState) -> String {
        switch state {
        case .locked: tr("scooter.settings.topSpeedLocked")
        case .unlocked: tr("scooter.settings.topSpeedUnlocked")
        case let .other(value): format("scooter.settings.topSpeedOther", Double(value) / 10)
        }
    }

    static func scooterTopSpeedWrite(_ result: TopSpeedWrite) -> String {
        switch result {
        case let .confirmed(state): format("scooter.settings.topSpeedConfirmed", scooterTopSpeedState(state))
        case let .mismatch(state): format("scooter.settings.topSpeedMismatch", scooterTopSpeedState(state))
        case .unreadable: tr("scooter.settings.topSpeedUnreadable")
        }
    }

    static var scooterFeatures: String { tr("scooter.settings.features") }
    static var scooterFeaturesFooter: String { tr("scooter.settings.featuresFooter") }
    static var scooterSettingWhileRiding: String { tr("scooter.settings.settingWhileRiding") }
    static var scooterClock: String { tr("scooter.settings.clock") }

    static func scooterFeature(_ id: ScooterFeature.ID) -> String {
        tr("scooter.feature.\(id.rawValue)")
    }

    static func scooterFeatureFooter(_ id: ScooterFeature.ID) -> String? {
        switch id {
        case .streamlineTaillight, .indicatorSound: nil
        default: tr("scooter.feature.\(id.rawValue).footer")
        }
    }

    static var scooterRecoveryFooter: String { tr("scooter.settings.recoveryFooter") }
    static var scooterPairing: String { tr("scooter.settings.pairing") }
    static var scooterAdvanced: String { tr("scooter.screen.advanced") }
    static var scooterAdvancedHint: String { tr("scooter.screen.advancedHint") }
    static var scooterDetails: String { tr("scooter.screen.details") }

    static func scooterFeatureWrite(_ id: ScooterFeature.ID, _ result: FeatureWrite) -> String {
        switch result {
        case let .confirmed(on): format("scooter.settings.featureConfirmed", scooterFeature(id), onOff(on))
        case let .mismatch(on): format("scooter.settings.featureMismatch", scooterFeature(id), onOff(on))
        case .unreadable: tr("scooter.settings.featureUnreadable")
        }
    }

    static var scooterRecovery: String { tr("scooter.settings.recovery") }

    static func scooterRecoveryLevel(_ level: EnergyRecovery?) -> String {
        switch level {
        case .off: tr("scooter.recovery.off")
        case .weak: tr("scooter.recovery.weak")
        case .strong: tr("scooter.recovery.strong")
        case nil: tr("scooter.recovery.unknown")
        }
    }

    static func scooterRecoveryWrite(_ result: RecoveryWrite) -> String {
        switch result {
        case let .confirmed(level): format("scooter.settings.recoveryConfirmed", scooterRecoveryLevel(level))
        case let .mismatch(level): format("scooter.settings.recoveryMismatch", scooterRecoveryLevel(level))
        case .unreadable: tr("scooter.settings.featureUnreadable")
        }
    }

    static func scooterClockState(_ sync: TimeZoneSync) -> String {
        switch sync {
        case let .alreadySet(minutes): format("scooter.settings.clockMatches", utcOffset(minutes))
        case let .updated(_, minutes): format("scooter.settings.clockUpdated", utcOffset(minutes))
        case let .mismatch(minutes): format("scooter.settings.clockMismatch", utcOffset(minutes))
        case .unreadable: tr("scooter.settings.notAvailable")
        }
    }

    static func utcOffset(_ minutes: Int) -> String {
        String(format: "UTC%@%d:%02d", minutes < 0 ? "−" : "+", abs(minutes) / 60, abs(minutes) % 60)
    }

    private static func onOff(_ on: Bool) -> String {
        tr(on ? "scooter.settings.on" : "scooter.settings.off")
    }

    static func scooterActionOutcome(_ outcome: VehicleActionOutcome) -> String {
        switch outcome {
        case .sent: tr("scooter.settings.sent")
        case .stateChanged: tr("scooter.settings.stateChanged")
        case .stateUnchanged: tr("scooter.settings.stateUnchanged")
        }
    }

    static func scooterError(_ error: ScooterError) -> String {
        switch error {
        case .bluetoothOff: tr("scooter.error.bluetoothOff")
        case .bluetoothDenied: tr("scooter.error.bluetoothDenied")
        case .notFound: tr("scooter.error.notFound")
        case .serialRejected: tr("scooter.error.serialRejected")
        case .passwordRejected: tr("scooter.error.passwordRejected")
        case .heldByOtherApp: tr("scooter.error.heldByOtherApp")
        case .connectionFailed, .noCompatibleService, .disconnected, .timeout, .unexpectedResponse: tr("scooter.error.failed")
        }
    }

    static func defaultVoice(_ name: String?) -> String {
        name.map { format("settings.voice.defaultNamed", $0) } ?? tr("settings.voice.default")
    }

    static func guidanceModeName(_ mode: GuidanceMode) -> String {
        switch mode {
        case .all: tr("settings.guidance.all")
        case .alertsOnly: tr("settings.guidance.alertsOnly")
        case .off: tr("settings.guidance.off")
        }
    }

    static func timeMode(_ mode: TripTimeSheet.Mode) -> String {
        switch mode {
        case .now: tr("time.mode.now")
        case .departAt: tr("time.mode.departAt")
        case .arriveBy: tr("time.mode.arriveBy")
        }
    }

    static func stop(_ number: Int) -> String { format("preview.stop", number) }
    static func route(_ number: Int) -> String { format("preview.route", number) }
    static func routeUnverified(_ distance: String) -> String { format("preview.route.unverified", distance) }
    static func routeUnavoidable(_ distance: String) -> String { format("preview.route.unavoidable", distance) }
    static func leaveAt(_ time: String) -> String { format("preview.leaveAt", time) }
    static func verifiedOnlyRemaining(_ distance: String) -> String { format("preview.verifiedOnly.remaining", distance) }
    static func tooManyStops(_ max: Int) -> String { format("error.tooManyStops", max) }

    static func languageName(_ choice: LanguageChoice) -> String {
        switch choice {
        case .system: tr("settings.language.system")
        case .dutch: tr("settings.language.dutch")
        case .english: tr("settings.language.english")
        }
    }

    static func appearanceName(_ choice: AppearanceChoice) -> String {
        switch choice {
        case .system: tr("settings.appearance.system")
        case .light: tr("settings.appearance.light")
        case .dark: tr("settings.appearance.dark")
        }
    }

    static func mapStyleName(_ style: MapStyle) -> String {
        tr("settings.mapStyle.\(style.rawValue)")
    }

    static func reportQueued(_ pending: Int) -> String { format("ride.report.queued", pending) }
    static func unverifiedAhead(_ distance: String, length: String, language: Language = .current) -> String {
        format("ride.unverifiedAhead", distance, length, language: language)
    }

    static func unverifiedInside(_ remaining: String, language: Language = .current) -> String {
        format("ride.unverifiedInside", remaining, language: language)
    }
    static func speedLimit(_ kmh: Int) -> String { format("ride.speedLimit", kmh) }
    static func reroutes(_ count: Int) -> String { format("ride.sim.reroutes", count) }
    static func nextStop(_ name: String) -> String { format("ride.nextStop", name) }
    static var then: String { tr("ride.banner.then") }
    static func thenManeuver(_ text: String) -> String { format("ride.banner.then.accessibility", text) }
    static func roundaboutExit(_ number: Int) -> String { format("ride.banner.exit", number) }
    static func roundaboutExitSpoken(_ number: Int) -> String { format("ride.banner.exit.accessibility", number) }
    static func lanes(valid: Int, total: Int) -> String { format("ride.banner.lanes", valid, total) }
    static func editFailed(_ reason: String) -> String { format("ride.edit.failed", reason) }

    static func resumeMessage(_ ride: ActiveRide) -> String {
        guard !ride.stops.isEmpty else { return format("resume.message", ride.destination.title) }
        return format("resume.message.stops", ride.destination.title, ride.stops.map(\.title).joined(separator: ", "))
    }

    static func chip(for stretchClass: StretchClass, limit: Int?) -> String {
        let label = switch stretchClass {
        case .carriageway: chipCarriageway
        case .mopedPath: chipMopedPath
        case .unverified: chipUnverified
        case .forbidden: chipForbidden
        }
        guard let limit else { return label }
        return format("chip.withLimit", label, limit)
    }

    static func skipsUnverified(_ distance: String) -> String { format("preview.verifiedOnly.skips", distance) }
    static func stillUnverified(_ distance: String) -> String { format("preview.verifiedOnly.still", distance) }
    static func arrive(_ time: String) -> String { format("preview.arrive", time) }

    static func label(for stretchClass: StretchClass) -> String {
        switch stretchClass {
        case .carriageway: carriageway
        case .mopedPath: mopedPath
        case .unverified: unverified
        case .forbidden: forbidden
        }
    }

    static func message(for error: Error) -> String {
        switch error {
        case let error as RouteRequestError:
            switch error {
            case .unauthorized: return unauthorized
            case .noRoute: return noRoute
            case .serviceUnavailable: return serviceUnavailable
            case .classificationFailed: return classificationFailed
            case .tooManyStops: return tooManyStops(TripPlan.maxStops)
            case .conflictingTimes: return conflictingTimes
            case .alternativesNeedTwoPoints: return alternativesNeedTwoPoints
            case .stopsUnsupported: return tr("error.stopsUnsupported")
            case let .http(status, code): return format("error.http", status, code.map { " (\($0))" } ?? "")
            }
        case is RouteParseError, is DecodingError: return routeParseFailed
        case is URLError: return networkFailed
        default: return routeParseFailed
        }
    }
}
