# ios

Native SwiftUI app (iOS 18+). So far it covers destination search and the route preview against the API in `api/`.
Guidance comes in a later slice.

## Stack (pinned exactly)

| Package | Version | Why |
|---|---|---|
| [Ferrostar](https://github.com/stadiamaps/ferrostar) (`FerrostarCore`) | 0.59.0 | OSRM parsing now, guidance later via `RouteProvider.customProvider` |
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

This test needs the local stack: Valhalla on 8002 (`routing/serve.sh start`) and the API on 8080 with the same key as
`Local.xcconfig`.

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
- `Naviscoot/App/Strings.swift` holds every UI string, so a switch to Dutch stays cheap.
