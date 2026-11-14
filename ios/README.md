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
- Map tiles: OpenFreeMap `liberty` style, no key. Search: PDOK Locatieserver (`suggest`, then `lookup` on selection)
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
- the API client and OSRM parsing through Ferrostar;
- the stretch-to-polyline split and its geometry check;
- totals, error mapping and formatting;
- PDOK parsing and the search merge.

### UI proof (`NaviscootUITests` scheme)

Two classes. `SearchAndPreviewUITests` is described below. `RideUITests` drives a simulated ride (about 2.5 minutes):
- From the `verified-only-north-south` origin at 120 km/h it checks that the banner shows a distance and then "Holkerpad".
  It also checks that every line handed to the synthesizer is `nl-NL`, including a pre-turn line ("Over 50 meter, Rechts
  afslaan.").
- It taps Report and finds that exact `route_id` in `GET /reports`, with the position and the tap time.
- It taps Detour (150 m off the route) and expects a new `route_id` from the API, "reroutes 1", a moving banner distance
  and a new spoken line.
- From a point 1.4 km before the 483 m unverified way, computed from the API's own geometry, at 90 km/h it expects the
  chip "Unverified path in …, for 483 m" and one Dutch warning. On the stretch it expects "On unverified path, … left",
  the stretch chip "Unverified path, limit 30" and the limit sign 30. The warning must clear after the stretch.

This test needs an API with the same key as `Local.xcconfig`. By default that's the local stack: Valhalla on 8002
(`routing/serve.sh start`) and the API on 8080. To run it against the deployed API, add
`TEST_RUNNER_NAVISCOOT_API_BASE_URL=https://naviscoot.appj.nl`. The proof's reports then land on the server.

```sh
xcrun simctl location $U set 52.2977646,5.445363
TEST_RUNNER_NAVISCOOT_API_KEY=<key> TEST_RUNNER_SCREENSHOT_DIR=/some/dir \
  xcodebuild -project Naviscoot.xcodeproj -scheme NaviscootUITests -destination "platform=iOS Simulator,id=$U" $FLAGS test
```

The test runs inside the simulator (XCUITest), so it never touches the Mac's cursor or focus.
1. It types the address "Woudenbergseweg 42 Maarsbergen" and expects an address result, then types "Amersfoort
   Centraal" and expects a place result.
2. It opens the preview from the `verified-only-north-south` origin. The case's destination coordinate itself has no
   address that keeps the 483 m unverified stretch; Woudenbergseweg 42 does.
3. It asserts that the time, distance and per-class rows equal the API's own response for the same request.
4. It zooms to the unverified stretch, then switches on "Verified roads only" and checks the API's verified-only
   figures, with unverified at 0 m.
5. Screenshots are written to `SCREENSHOT_DIR`.

`idb` taps don't work with Xcode 27: idb_companion 1.1.8 looks for SimulatorKit in its old location. That is why the
proof uses XCUITest.

## Layout

- `Naviscoot/Routing/`: `NaviscootClient` (`POST /route`, `x-api-key`, `format: osrm`) and `RouteParser`.
  - The parser runs Ferrostar's OSRM parser (`polylinePrecision: 6`) on the body and decodes `routes[0].duration` and
    the top-level `naviscoot` key separately.
  - It splits the geometry into one segment per stretch, using inclusive shape indices that adjacent stretches share.
  - It rejects a response whose last stretch doesn't end at the last geometry point.
- `Naviscoot/Search/`: `PDOKClient`, `PlaceSearch`, `SearchMerge`, `SearchModel`, `SearchView`.
  - The merge interleaves the two lists. Addresses go first when the query contains a digit.
  - It drops a place whose name equals an address title, ignoring case and diacritics, and caps the list at 12.
- `Naviscoot/Preview/`: `PreviewModel`, `PreviewView`, `RouteMapView`.
  - Verified stretches are drawn solid blue, unverified ones dashed orange, and `forbidden` (graph/CSV drift) dashed red.
  - Tapping the "Unverified cycle path" row zooms the map to those stretches.
- `Naviscoot/Ride/`: guidance.
  - `RideModel` owns a `FerrostarCore` built with `customRouteProvider: NaviscootRouteProvider`.
    - Start navigates the plan the preview already holds.
    - The provider only serves reroutes: `POST /route` from the user's location to the last remaining waypoint, with the
      `verified_only` choice captured at Start.
    - Every plan goes into a lock-protected `PlanBook` keyed by Ferrostar's `Route`, so the `naviscoot` metadata of a reroute
      is found again.
  - `RideNavigationDelegate` accepts a reroute on the main thread: the simulator switches to the new route first, then
    `startNavigation`.
    - Deviation: static threshold, 40 m, needing an accuracy of 25 m or better. Steps advance at 30 m before and 5 m after
      the maneuver.
  - `DutchSpeechSynthesizer` wraps `AVSpeechSynthesizer` for Ferrostar's `SpokenInstructionObserver`.
    - Valhalla's SSML has no language, so every utterance is rebuilt as plain text with the `nl-NL` voice.
    - Each line is recorded. In a simulated ride the log is shown in the debug panel; its accessibility value is the full
      log, which the UI proof reads.
  - `RouteProgress.swift` maps progress to a position on the route.
    - Global shape index = start of the current step (step geometries share their joints; the final arrive step is a
      degenerate two-point step) + Ferrostar's `currentStepGeometryIndex`.
    - The snapped position is then projected onto the neighbouring segments.
    - The unverified warning appears 1,000 m before a stretch and stays while on it. It is spoken once per stretch, keyed by
      way ids, so a reroute doesn't repeat it.
    - The speed limit comes from the API's `speed_limits`.
  - `ReportQueue`: reports are stored in Application Support until `POST /reports` accepts them, retried after 10/30/60/120/300 s
    and at app start. A 400/413/422 is dropped. The time is the tap time, kept through retries.
  - `RideSimulator` is a `LocationProviding` that drives along the route at a set speed (0.5 s ticks). Detour shifts it
    150 m sideways until the reroute arrives.
- Background modes `audio` and `location`; `CoreLocationProvider(activityType: .otherNavigation,
  allowBackgroundLocationUpdates: true)` on a device. The screen stays on during a ride (`isIdleTimerDisabled`).
- `Naviscoot/App/Strings.swift` holds every UI string, so a switch to Dutch stays cheap.

### Simulated rides

On the simulator a ride is simulated by default; on a device it uses CoreLocation. Launch arguments (UserDefaults):

| Argument | Default | Meaning |
|---|---|---|
| `-NaviscootSimulateRide YES/NO` | YES on the simulator, NO on a device | Use `RideSimulator` instead of CoreLocation |
| `-NaviscootSimSpeedKmh 120` | 45 | Simulated speed |
| `-NaviscootSimOrigin 52.29,5.44` | none | Fixed start position for the preview (simulated rides only) |

A simulated ride shows a debug panel with the route id, the reroute count, a Detour button and the last spoken line.
