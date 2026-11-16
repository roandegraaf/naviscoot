# ios

Native SwiftUI app (iOS 18+): destination search, the route preview and turn-by-turn guidance against the API in `api/`.

## Stack (pinned exactly)

| Package | Version | Why |
|---|---|---|
| [Ferrostar](https://github.com/stadiamaps/ferrostar) (`FerrostarCore`) | 0.59.0 | OSRM parsing and guidance (`FerrostarCore` with a custom route provider) |
| [maplibre/swiftui-dsl](https://github.com/maplibre/swiftui-dsl) (`MapLibreSwiftUI`, `MapLibreSwiftDSL`) | 0.26.1 | SwiftUI map with declarative sources and layers |
| [MapLibre Native](https://github.com/maplibre/maplibre-gl-native-distribution) | 6.24.0 | Map renderer |

- Ferrostar declares swiftui-dsl as `from: 0.26.1`. Left alone, SPM floats it to 0.27.0, which needs MapLibre 7.
- Ferrostar 0.59.0's own demo resolves swiftui-dsl 0.26.1 with MapLibre 6.24.0, so `project.yml` pins all three with
  `exactVersion`.
- The real pin is `Naviscoot.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`, committed. It also
  pins swift-syntax 602.0.0.
- Map tiles: OpenFreeMap `liberty` style, no key. The `dark` style (the night map) is a bundled Liberty recolour,
  `Naviscoot/Resources/liberty-night.json`, on the same OpenFreeMap tiles, sprites and fonts. Search: PDOK Locatieserver (`suggest`, then `lookup` on selection)
  for addresses and `MKLocalSearch` (points of interest) for places such as stations.

## Setup

```sh
cp ios/Config/Local.xcconfig.example ios/Config/Local.xcconfig   # gitignored; set the API key the API runs with
```

- `Config/App.xcconfig` includes `Local.xcconfig` optionally. Without it the app builds but shows "not configured".
- In an xcconfig file `//` starts a comment, so the URL is written as `http:/$()/127.0.0.1:8080`.
- `NSAllowsLocalNetworking` lets the app call plain `http://127.0.0.1`.
- For the deployed API, set `NAVISCOOT_API_BASE_URL = https:/$()/naviscoot.appj.nl` and the production key, which is kept
  in Coolify (see `routing/README.md` "Deploy (Coolify)").

### Scooter keys

`scripts/scooter-keys.sh [serial]` copies the scooter's serial, BLE password and (if stored) seat/power ident from the Mac
login Keychain into `Local.xcconfig`. The Keychain items are generic passwords with account = serial and service
`Naviscoot scooter BLE password` / `Naviscoot scooter BLE ident`, each 32 hex characters:

```sh
security add-generic-password -a <serial> -s "Naviscoot scooter BLE ident" -w <32 hex>
ios/scripts/scooter-keys.sh
```

- On launch, a device build fills the serial and the iPhone Keychain from these values, but only where they're still
  empty, so anything entered in Settings wins. Simulator builds skip it, so UI tests still start unconfigured.
- The values end up in the built app's `Info.plist` in plain text. Fine for your own device builds; don't hand out an
  `.ipa` built with them.

The project is generated from `project.yml` with XcodeGen (`xcodegen generate` in `ios/`). The generated project is
committed, so building doesn't need XcodeGen.

## Build and test

Command-line builds need `-skipMacroValidation`: swiftui-dsl ships Swift macros, and `xcodebuild` refuses untrusted
macros otherwise.

```sh
cd ios
FLAGS="-derivedDataPath build/dd -skipMacroValidation -skipPackagePluginValidation"
xcodebuild -project Naviscoot.xcodeproj -scheme Naviscoot -destination 'generic/platform=iOS Simulator' $FLAGS build

U=<simulator udid>    # an iOS 27.2 simulator, booted headless: xcrun simctl boot $U
xcodebuild -project Naviscoot.xcodeproj -scheme Naviscoot -destination "platform=iOS Simulator,id=$U" $FLAGS test
```

`Naviscoot` runs the unit tests (offline, fixtures in `NaviscootTests/Fixtures`):
- the API client and OSRM parsing through Ferrostar, including a multi-stop route (`route-multi-stop.json`) and one
  with alternatives (`route-alternatives.json`), both captured from the local API;
- the stretch-to-polyline split and its geometry check;
- totals, error mapping and formatting;
- PDOK parsing and the search merge.

### UI proof (`NaviscootUITests` scheme)

A small smoke set: about one test per core flow, seven tests in four classes, about 5 minutes of test time (5 with the
build). The detailed behaviour (parsing, totals, stops, resume, voice, appearance, trip stats) is covered by the unit
tests, which run in seconds. Run the whole set when a change touches several screens; otherwise run only the classes for
the screens you changed with `-only-testing:NaviscootUITests/<Class>`.

| Class | Flow it proves |
| --- | --- |
| `HomeDrawerUITests` | Seeded places and recent trips show in the drawer on launch; "See all" and a recent trip open trip history and close back to the drawer. Searching expands the drawer, a result opens the preview, and backing out brings the drawer back with the query kept. With `-NaviscootSimETA`, Home 5 km away reads "12 min · …" and opens the preview; a failing fake shows "5.0 km · …" only. A seeded parking spot shows a scooter pin on the map that offers "Walk there"; with `-NaviscootSimScooter charging` the map's strip reads "64%, 31 km, Connected" and opens the scooter screen: big battery and range, Open seat / Switch on / Switch off reachable without scrolling (Open seat answers), health, cycles, temperature and "Full in about 1 h 35 min", a Details page with the full battery report, and an Advanced page with the speed limit, top speed, energy recovery, feature toggles and clock. The all-carriageway route to Home lists no 0 m rows and no verified-only toggle; dragging the second stop above the first swaps them (the deployed API ignores waypoints, so that route shows the stops error); with `-NaviscootSimRoutesFile <route-alternatives.json>` the preview draws time bubbles on the alternatives and tapping one selects its route. |
| `TripsUITests` | Search → preview → Start → End through the alert at 60 km/h: a ride ended at once isn't recorded, one ended after 45 s is, with plausible distance, duration and speed. |
| `StopRideUITests` | A ride killed mid-way is offered for resuming on the next launch; declining ("End ride") forgets it. |
| `LandscapeUITests` | In landscape the side panel holds the drawer, search results and the preview's controls, all reachable and unclipped, the scooter strip included (fake scooter); rotating back keeps the query. |

Every launch pins the language with `-settings.language en` and turns verified-only and the three avoid settings off,
so the proof doesn't depend on the simulator's locale or on settings a previous run left behind. Every launch also
passes `-NaviscootDiscardActiveRide YES`, except the resume relaunches. `HomeDrawerUITests` seeds Home, Work, a
favourite, a recent and two trips with `-NaviscootSeedHome YES`, and a parking spot with `-NaviscootSeedParked lat,lon`.
`-NaviscootSimScooter charging|riding` connects a fake scooter: a real `NinebotSession` over `SimulatedScooter`, a
register map at 64 %, 31 km and a charging battery report. No Bluetooth, and nothing is saved. All of these are DEBUG only.

The previews and rides talk to the API with the key from `Local.xcconfig`. `TripsUITests`, `StopRideUITests` and
`LandscapeUITests` skip without `TEST_RUNNER_NAVISCOOT_API_KEY`. The default base URL is the local stack (API on 8080); add
`TEST_RUNNER_NAVISCOOT_API_BASE_URL=https://naviscoot.appj.nl` to run against the deployed API.

```sh
TEST_RUNNER_NAVISCOOT_API_KEY=<key> TEST_RUNNER_NAVISCOOT_API_BASE_URL=https://naviscoot.appj.nl \
TEST_RUNNER_SCREENSHOT_DIR=/some/dir \
  xcodebuild -project Naviscoot.xcodeproj -scheme NaviscootUITests -destination "platform=iOS Simulator,id=$U" $FLAGS test
```

The tests run inside the simulator (XCUITest), so they never touch the Mac's cursor or focus. If unit tests show Dutch
strings where English is expected, the simulator app kept a Dutch language setting from an earlier run:
`xcrun simctl uninstall $U nl.naviscoot.app` resets it.

Debug launch options the tests use (DEBUG builds only): `-NaviscootSimOrigin lat,lon` fixes the location,
`-NaviscootSimulateRide YES` with `-NaviscootSimSpeedKmh` drives rides, `-NaviscootSeedHome YES` seeds the drawer, and
`-NaviscootSimETA <seconds|fail>` replaces the drawer's live ETA requests with a fixed answer or a failure.

`idb` taps don't work with Xcode 27: idb_companion 1.1.8 looks for SimulatorKit in its old location. That is why the
proof uses XCUITest.

## Layout

- The search screen shows only the map, the field and its two buttons. Saved places and recents (or the results) open
  when the field is focused and close with the back chevron (which also clears the query), a map tap, a long-press
  pin, or a chosen place.
- The portrait preview sheet minimises to the summary and Start by a swipe or tap on its handle; the map refits to the
  area it frees. The landscape side panel doesn't minimise.
- `Design/map-style/make_night_style.py` writes `liberty-night.json` from the live Liberty style (or a saved copy passed
  as an argument): `python3 ios/Design/map-style/make_night_style.py`. OpenFreeMap refuses Python's default
  User-Agent, so the script sends its own. Colours are set per layer role; the script fails on a coloured Liberty layer
  it has no colour for. Rerun it when OpenFreeMap changes Liberty, since the bundled copy pins its sprite version.
- `Design/icon/`: the app icon. `render.py` holds the three concepts (`route`, the default; `arrow`; `pin`), writes
  their SVGs to `svg/` and their PNGs to `png/` (with `concepts.png` as a preview sheet), and fills
  `Naviscoot/Resources/Assets.xcassets`: `AppIcon` (light, dark, tinted), `LaunchMark` (light, dark) and
  `LaunchBackground`. It needs `rsvg-convert` and ImageMagick 7. To swap the icon, change `DEFAULT_CONCEPT` and run
  `python3 ios/Design/icon/render.py`. The launch screen is `UILaunchScreen` in `project.yml`.
- `Naviscoot/Routing/`: `NaviscootClient` (`POST /route`, `x-api-key`, `format: osrm`) and `RouteParser`.
  - `RouteOptions` carries stops, alternatives, a departure or arrival time and the avoid options. With the default
    options the request body is the plain two-point one. `routes(…)` returns every route; `route(…)` the first.
  - The parser runs Ferrostar's OSRM parser (`polylinePrecision: 6`) on the body and decodes each `routes[i].duration`
    and the top-level `naviscoot` key separately. Route `i` gets `naviscoot` for `i = 0` and
    `naviscoot.alternates[i - 1]` after that. A count mismatch is an error.
  - Stretch, speed-limit and leg indices all point into the route's whole geometry, also across stops
    (`api/README.md`, "Multi-stop routes"). The parser checks that `naviscoot.legs` covers the geometry end to end.
  - It splits the geometry into one segment per stretch, using inclusive shape indices that adjacent stretches share.
  - It rejects a response whose last stretch doesn't end at the last geometry point.
- `Naviscoot/Search/`: `PDOKClient`, `PlaceSearch`, `SearchMerge`, `SearchModel`, `SearchView`.
  - The merge interleaves the two lists. Addresses go first when the query contains a digit.
  - It drops a place whose name equals an address title, ignoring case and diacritics, and caps the list at 12.
- `Naviscoot/Preview/`: `TripPlan`, `PreviewModel`, `PreviewView`, `TripTimeSheet`, `RouteMapView`.
  - `TripPlan` is the planner state: start (current location or an address), up to 8 stops, destination and an optional
    departure or arrival time. It builds the request: no stops means `alternatives: 2`; a stop within 25 m of the point
    before it (or a last stop on the destination) is dropped; the avoid options come from settings.
  - Route 0 is selected by default and Start rides the selected route, with the stops that were actually sent. Start is
    offered only from the current location; otherwise a hint explains why.
  - Depart-at shows departure + duration as the arrival; arrive-by shows arrival − duration as "leave at".
  - Unselected alternatives are drawn as a grey line under the selected route; stops are numbered dots.
  - Verified stretches are drawn solid blue, unverified ones dashed orange, and `forbidden` (graph/CSV drift) dashed red.
  - Tapping the "Unverified cycle path" row zooms the map to those stretches.
- `Naviscoot/Ride/`: guidance.
  - `RideModel` owns a `FerrostarCore` built with `customRouteProvider: NaviscootRouteProvider`.
    - Start navigates the plan the preview already holds.
    - The provider only serves reroutes: `POST /route` from the user's location through every remaining waypoint Ferrostar
      hands it (the last is the destination, the others go as `waypoints`), with the `verified_only`, avoid and language
      captured at Start. A route for a request with stops must carry stops + 2 waypoints, else it's
      `RouteRequestError.stopsUnsupported` (an API that drops `waypoints`, like the pre-slice-2 deployment). It reports each outcome; a failure shows a warning until a reroute succeeds or the rider is back on
      the route. Ferrostar retries every 5 s while off route (`minimumMovementBeforeRecalculation = 0`, so a rider who
      stopped gets retries too).
    - Stops: Ferrostar drops a stop from `remainingWaypoints` within 100 m of it. The model counts what is left, names the
      reached stop in a spoken line of its own (Valhalla's intermediate arrival says "destination") and shows the next stop.
    - The active ride (destination, remaining stops, verified-only, avoid, language) is written to
      `Application Support/active-ride.json` at Start and at every stop, and removed on End, on arrival and when the rider
      declines to resume. At launch a saved ride is offered; Resume plans a fresh route from the current position through
      the remaining stops with the saved options.
    - End asks for confirmation unless the rider has arrived. Revoked or reduced-accuracy location shows a warning with a
      Settings button.
    - Mid-ride edits (`RouteEdit`): "Add a stop" puts the new stop before the remaining ones, "Change destination" keeps
      them. The new route is planned from the current position with the ride's own options and swapped in like a reroute,
      without ending the ride; the saved ride follows. A failed plan is shown and the old route keeps guiding. The edited
      route starts a new `PlanBook` generation, so a reroute requested for the old waypoints can't undo the edit, and its
      unverified warnings are spoken again.
    - Camera (`RideCamera`): following by default; a pan, pinch, rotate or tilt (swiftui-dsl's gesture
      `CameraChangeReason`, read from `onMapViewProxyUpdate(.realtime)`) switches to free, where `mapCameraDisabled` stops
      state updates from moving the map. Overview fits the position and the route ahead into the part of the screen the
      overlays leave free. Recenter returns to following.
    - Every plan goes into a lock-protected `PlanBook` keyed by Ferrostar's `Route`, so the `naviscoot` metadata of a reroute
      is found again.
  - `RideNavigationDelegate` accepts a reroute on the main thread: the simulator switches to the new route first, then
    `startNavigation`.
    - Deviation: static threshold, 40 m, needing an accuracy of 25 m or better. Steps advance at 30 m before and 5 m after
      the maneuver.
  - `GuidanceSpeechSynthesizer` wraps `AVSpeechSynthesizer` for Ferrostar's `SpokenInstructionObserver`.
    - Valhalla's SSML has no language, so every utterance is rebuilt as plain text with the voice for the ride's
      language (`nl-NL` or `en-GB`, fixed at Start like `verified_only`; the API request's `language` carries the same
      code, so Valhalla's instructions and reroutes match).
    - Each line is recorded. In a simulated ride the log is shown in the debug panel; its accessibility value is the full
      log, which the UI proof reads.
  - `RouteProgress.swift` maps progress to a position on the route.
    - Global shape index = start of the current step (step geometries share their joints; every arrive step is a
      degenerate two-point step that spans no geometry, so an intermediate one doesn't shift later legs) + Ferrostar's
      `currentStepGeometryIndex`.
    - The snapped position is then projected onto the neighbouring segments.
    - The unverified warning appears 1,000 m before a stretch and stays while on it. It is spoken once per stretch, keyed by
      way ids, so a reroute doesn't repeat it.
    - The speed limit comes from the API's `speed_limits`.
  - `ReportQueue`: reports are stored in Application Support until `POST /reports` accepts them, retried after 10/30/60/120/300 s
    and at app start. A 400/413/422 is dropped. The time is the tap time, kept through retries.
  - `RideSimulator` is a `LocationProviding` that drives along the route at a set speed (0.5 s ticks). Detour shifts it
    150 m sideways until the reroute arrives.
- Background modes `audio` and `location`; on a device the ride uses `RideLocationProvider` (`.otherNavigation`,
  background updates on, `pausesLocationUpdatesAutomatically = false` so a wait at a light can't stop background guidance,
  blue indicator). When-in-use only. The screen stays on during a ride (`isIdleTimerDisabled`).
- Live Activity: the `NaviscootLiveActivity` widget extension (`NaviscootLiveActivity/`, sharing `Shared/RideActivityAttributes.swift`
  with the app; `NSSupportsLiveActivities`). The app resolves every text in its language and sends it in the content state, so the
  extension has no catalog or shared settings. `RideModel` starts it at Start (also on resume, after ending any leftover), sends a
  maneuver, street, destination, warning or language change at once and anything else at most every 5 s (60 s heartbeat, stale
  after 150 s), ends it at arrival with the arrived state (dismissed after 5 min) and removes it at End. A declined resume offer, or
  a launch with no ride to offer, ends every leftover activity.
- Watch app: the `NaviscootWatch` watchOS target (single-target SwiftUI app, `nl.naviscoot.app.watchkitapp`, embedded in
  `Naviscoot.app/Watch/` by the app's target dependency). `WatchShared/WatchRideMessage.swift` (Foundation only) is compiled into
  the app and the watch: the payload (the Live Activity's resolved texts plus an optional haptic cue, sent as JSON `Data` under
  one key) and `WatchInbox`, the watch's gate (newest state wins, each cue plays once, cues older than 10 s are dropped).
  `Naviscoot/Ride/RideWatch.swift`: `WatchCueTrigger` (the phone decides the taps: a turn once per maneuver within 120 m,
  skipping straight on and the arrival; an unverified stretch once per stretch; arrival once), `WatchThrottle` (milestones and
  cues at once and urgent, other changes at most every 2 s, 30 s heartbeat) and `PhoneWatchLink` (activated at launch; sends
  only when a watch is paired with the app installed: `updateApplicationContext` always, `sendMessage` too when urgent and
  reachable). End, a declined resume offer and a launch with no ride clear the watch. No routing on the watch.
- Settings and language (`Naviscoot/App/AppSettings.swift`, `Naviscoot/Settings/`):
  - `AppSettings` is one `@Observable` object backed by `UserDefaults` (`settings.language`: `system`/`nl`/`en`;
    `settings.verifiedOnlyByDefault`, `settings.avoidFerries`, `settings.avoidUnpaved`, `settings.avoidMainRoads`).
    The ride captures the avoid options at Start and sends them with every reroute. It's injected with `.environment`, and `AppSettings.shared` is the same instance.
  - `Strings` is the only place views get text from. It reads `Resources/Localizable.xcstrings` (`en` and `nl`, semantic
    keys, `extractionState: manual`) from the `.lproj` of the chosen language. Views read `AppSettings` through
    `Strings`, so Observation re-renders them when the language changes; no restart needed.
  - `Format` and `SpokenPhrases` (the app's own spoken warnings) take the language too. English uses British spelling
    to match Valhalla's `en-GB` ("metres").
  - "System" picks the first of the device's preferred languages that is Dutch or English, else English.
  - `DEVELOPMENT_TEAM` is not in `project.yml`; put yours in the gitignored `Config/Local.xcconfig` to run on a device.

### Simulated rides

On the simulator a ride is simulated by default; on a device it uses CoreLocation. Launch arguments (UserDefaults):

| Argument | Default | Meaning |
|---|---|---|
| `-NaviscootSimulateRide YES/NO` | YES on the simulator, NO on a device | Use `RideSimulator` instead of CoreLocation |
| `-NaviscootSimSpeedKmh 120` | 45 | Simulated speed |
| `-NaviscootSimOrigin 52.29,5.44` | none | Fixed start position for the preview and for resuming (simulated rides only) |
| `-NaviscootSimRerouteFailures 2` | 0 | The first N reroutes fail as if the API were unreachable (simulated rides only) |
| `-NaviscootSimEditFailures 1` | 0 | The first N mid-ride edits (add stop, change destination) fail as if the API were unreachable (simulated rides only) |
| `-NaviscootDiscardActiveRide YES` | NO | Forget a saved ride at launch instead of offering to resume it |
| `-NaviscootSimClock 2026-11-15T21:00:00Z` | none | The app's clock starts at this time and runs on from launch; drives the dark map at night |
| `-NaviscootResetPlaces YES` | NO | Empty the saved places (recents, favourites, Home, Work) at launch |

A simulated ride shows a debug panel with the route id, the ride's options, the reroute count, a Detour button, the camera
state (`camera=following|free|overview`, zoom, pitch and direction, the map centre and, in overview, whether the remaining route fits the uncovered
part of the screen), the map style (`sim.style`: `style=<name> layers=<route layers present>/5 features=<route features
drawn>`) and the last spoken line.
