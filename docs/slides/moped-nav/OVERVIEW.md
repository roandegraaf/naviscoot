# Naviscoot: legal moped navigation for iOS

## Goal
A personal iPhone turn-by-turn navigation app for a Dutch bromfiets (yellow plate, 45 km/h) that only
routes over ways where a bromfiets may legally ride. Existing apps either route over forbidden cycle
paths or hide behind subscriptions; the root cause is incomplete access data, so this project builds its
own fused access dataset first and a navigation app on top of it.

## Scope
- A fused bromfiets access dataset for a 50 km radius around Amersfoort (centre 52.156, 5.387),
  combining OpenStreetMap, NDW verkeersborden and WKD Verkeerstypen, plus a hand-maintained override list.
- A coverage audit that measures data quality before and after fusion.
- A self-hosted routing service on the `coolify-personal` instance: routing graph for all of the
  Netherlands, fused access applied inside the region, plain OSM quality outside it.
- A thin API in front of the routing engine that classifies every route stretch
  (carriageway / moped path / unverified) and stores "data is wrong here" reports.
- A native iOS app: destination search, route preview with a per-type distance breakdown,
  turn-by-turn guidance with Dutch voice, rerouting, speed and speed limit, report button.
- A regression suite of known legal edge cases that every graph rebuild must pass.

## Non-goals
- Snorfiets (blue plate), speed pedelec, brommobiel or any other vehicle class.
- Android, web or CarPlay clients.
- Offline routing. The active route and its map tiles stay cached; rerouting needs a connection.
- Public release, accounts, payments, App Store listing.
- Live traffic, roadworks, closures, speed cameras, milieuzones.
- Sign recognition on street-level imagery (Google Street View is prohibited by its terms; Mapillary is
  not needed for v1).
- Fused access outside the 50 km region.

## Key decisions & constraints
**Legal model (RVV 1990), bromfiets only**
- Allowed: carriageway by default; fiets/bromfietspad (sign G12a), which is mandatory when present.
- Forbidden: fietspad G11, onverplicht fietspad G13, footways, autosnelweg, autoweg, and ways closed by
  C1, C2 (against the direction), C9, C13 or C15.
- Not binding on a bromfiets: C6, C7, C10, C11, C12 (they address "motorvoertuigen").
- Speed limits used for ETA and display: 45 on the carriageway, 30 on a moped path inside the built-up
  area, 40 outside.
- Where a G12a path runs alongside a road, the carriageway is closed to the bromfiets
  (`moped=use_sidepath` in OSM).

**Data**
- OSM is the routing graph and the primary access source (`moped=*`, `traffic_sign=NL:G11/G12a/G13`,
  `motorroad`, `oneway:moped`, `zone:traffic`). `mofa=*` means snorfiets and must never grant moped access.
- NDW verkeersborden (CC0, API v5 or the bulk file on opendata.ndw.nu) is the independent cross-check.
  It is points, not segments: signs are map-matched to OSM ways and propagated until an end sign (G12b)
  or junction. Most G12a records date from 2022, so a more recently edited OSM way wins a conflict.
- WKD Verkeerstypen (`BRMFTS_H/T`) is a tie-breaker only; its own documentation reports 76-94% accuracy.
- Precedence: override list > OSM explicit tag > NDW sign > WKD > unknown.
- A cycle path that stays unknown after fusion is **allowed with a penalty**, never silently: it is
  marked "unverified" in the route, drawn differently, counted in the preview and announced while riding.
  A "verified roads only" alternative must always be available.
- One-way exemptions for mopeds rely on OSM `oneway:moped`; NDW sub-sign data cannot settle them.
- Fixes found along the way should also go back to OSM where possible.

**Routing**
- Valhalla, `motor_scooter` costing, self-hosted, with a patched `graph.lua`. Three known stock defects
  must be fixed: `moped=use_sidepath` is ignored, `mofa` leaks into moped access, and moped paths get an
  8 km/h speed that makes the router avoid them.
- The fused access is applied by rewriting tags in the OSM extract before the graph build, so the
  routing engine needs no second data source.
- Unverified stretches get their penalty through a reduced edge speed; the value is tuned against the
  regression routes. Proposed mechanism for "verified roads only": re-request with the unverified
  stretches excluded (`exclude_locations`) until none remain. Validate this in the routing slice.
- The graph is built locally with Docker and the finished tiles are uploaded; the server only serves.

**Service**
- Thin API in TypeScript (Node) in front of Valhalla: route + per-stretch classification, reports
  endpoint, static API key header. Valhalla itself is not exposed publicly.

**iOS**
- Native SwiftUI, Ferrostar for guidance (native Valhalla adapter, voice, rerouting, snapping) on
  MapLibre Native. Not React Native or Flutter: those Ferrostar bindings are pre-alpha.
- Map tiles from OpenFreeMap. Search: PDOK Locatieserver for addresses, Apple MapKit local search for
  points of interest. Voice: system speech, Dutch (`nl-NL`).
- Built for glanceability on a handlebar mount: large type, large touch targets, screen kept awake,
  guidance continues with the screen locked. Layout reference: `docs/mockup.html`.

**Repository**
- One repo: `data/` (Python pipeline), `routing/` (Valhalla config, patched Lua, build scripts),
  `api/` (TypeScript service), `ios/` (Xcode project), `docs/`.
- Downloaded and generated data is gitignored; every dataset is reproducible from a script.
- No code comments unless the reason is non-obvious.

## Preconditions & external dependencies
- Apple Developer account: available.
- An iPhone and a handlebar mount for real ride tests.
- `coolify-personal`: roughly 2 GB of free RAM and a few GB of disk (unmeasured estimate), and a
  hostname for the API (for example a subdomain you choose). Deploying needs your go-ahead.
- Xcode 27.2 and Docker are installed on this Mac.
- No paid services and no API keys from third parties are required.

## Building blocks
- Region extract and source downloads (OSM, NDW signs, WKD, NWB as the ID bridge).
- Coverage audit and an inspection map of unknown and conflicting cycle paths.
- Sign-to-way matching and access propagation.
- Fusion with precedence rules, override list and conflict report.
- Tag rewriting into a routable OSM extract.
- Patched Valhalla graph build and regression suite.
- API service: routing, classification, verified-only alternative, reports.
- Coolify deployment and one-command refresh.
- iOS app: search, preview, guidance, speed display, report button.

## Definition of Done
- [x] Coverage audit exists for the region
  GIVEN the 50 km region, WHEN the audit runs, THEN it reports cycle-path length per status (allowed, forbidden, unknown) and lists OSM-versus-NDW conflicts
- [x] Fusion measurably reduces unknown cycle paths
  GIVEN the audit before and after fusion, WHEN compared, THEN the unknown length is lower and both figures are in the report
- [x] An override wins over every source
  GIVEN a way marked forbidden in the override list, WHEN the graph is rebuilt and a route is requested across it, THEN the route avoids that way
- [x] Never routes over a forbidden way
  GIVEN the regression cases for G11, G13, footway, autoweg and autosnelweg, WHEN each route is requested, THEN no route uses the forbidden way
- [x] Uses moped paths instead of detouring
  GIVEN Utrecht Domplein to Amersfoort centre, WHEN a route is requested, THEN it follows the N237 corridor and is under 25 km (stock Valhalla gives 42.6 km)
- [x] Stays off the carriageway where the moped path is mandatory
  GIVEN a road tagged `moped=use_sidepath` with a parallel G12a path, WHEN routed along it, THEN the route uses the path, not the carriageway
- [x] Snorfiets tags grant nothing
  GIVEN a cycle path with `mofa=yes` and no moped information, WHEN routed, THEN it is treated as unverified, not as allowed
- [ ] Unverified stretches are reported per route
  GIVEN a route that crosses an unknown cycle path, WHEN the API responds, THEN that stretch is classified unverified and the totals per type add up to the route length
- [ ] A verified-only alternative is available
  GIVEN that same route, WHEN "verified roads only" is requested, THEN the result contains no unverified stretch
- [x] Routing outside the region still works
  GIVEN a destination 100 km from Amersfoort, WHEN a route is requested, THEN a route is returned
- [ ] The API is live and protected
  GIVEN the deployed service, WHEN called without the API key, THEN it is refused, and with the key it returns a route
- [ ] Data refresh is one command
  GIVEN newer OSM and NDW data, WHEN the refresh command runs, THEN it rebuilds the fused extract and graph and fails loudly if a regression case breaks
- [ ] Search finds addresses and places
  GIVEN the app, WHEN typing a street address or a place such as a station, THEN both appear and selecting one opens the route preview
- [ ] Preview shows what the route consists of
  GIVEN a selected destination, WHEN the preview opens, THEN it shows time, distance, the distance per type and unverified stretches drawn differently on the map
- [ ] Turn-by-turn guidance with Dutch voice
  GIVEN a simulated ride in the iOS simulator, WHEN approaching a turn, THEN the banner shows distance and street and a Dutch instruction is spoken
- [ ] Reroutes when off route
  GIVEN a simulated ride that leaves the route, WHEN the deviation is detected, THEN a new route is requested and guidance continues
- [ ] Warns before an unverified stretch
  GIVEN a route with an unverified stretch, WHEN approaching it, THEN a warning is shown and spoken
- [ ] Report button records the location
  GIVEN a ride in progress, WHEN the report button is tapped, THEN the position and time are stored on the server and retrievable as a list
- [ ] Guidance continues with the screen locked `[user-gated]`
  GIVEN a real iPhone on a ride, WHEN the screen is locked, THEN voice instructions keep coming
- [ ] A real ride is legal end to end `[user-gated]`
  GIVEN a ride of at least 15 km through town and countryside, WHEN following the app, THEN it never directs onto a path or road closed to a bromfiets

## Open questions
- App interface language: English labels with Dutch voice (current assumption) or fully Dutch.
- The hostname for the API on `coolify-personal`.
- Exact penalty for unverified stretches; to be tuned against real routes.
- Whether confirmed corrections are also submitted to OpenStreetMap by you (needs an OSM account).
