# Progress — moped-nav

## Current state
**Slices done:** 1 (audit), 2 (fusion), 3 (routing graph + regression), 4 (thin API, local only), 5 (one-command refresh, local), 6 (iOS search + route preview), 7 (iOS guidance, voice, reroute, warning, reports; local API). One commit per slice on top of 0423a8b. `docs/audit/*.md` is committed. These are gitignored: `docs/audit/map.html`, `docs/slides/*/status/`, `api/data/`, `routing/build/`, `ios/build/`, `ios/Config/Local.xcconfig`.

**Only open automatable item:** "The API is live and protected". The user approved the deploy: hostname `naviscoot.appj.nl` (wildcard `*.appj.nl` exists), server `localhost` on `coolify-personal` (https://coolify.servertj.nl), repo on their GitHub.
- Done: the compose stack (proven locally), `routing/deploy-graph.sh`, and the private repo https://github.com/roandegraaf/naviscoot (`master`).
- Blocked on access the agent doesn't have: the Coolify API (its Keychain token read was denied; the `coolify-personal` MCP isn't loaded in worker sessions) and SSH to the server for the graph upload.
- Also open: the two `[user-gated]` real-ride items and the placeholder reviews.

**Invariants in force**
- Region = 50 km around 52.156, 5.387. Cycle path = OSM `highway=cycleway`; status per whole way. `mofa=*` is never moped evidence, anywhere (fusion, rewrite, Lua).
- Precedence: `data/overrides.csv` > NDW newer and unambiguous > explicit OSM tag > NDW direct > NDW propagated > unknown. The user still has to review the 5 forbidden → allowed flips and the Valeriusplein override (`docs/audit/conflicts.md`).
- Rewrite: allowed → `moped=designated`, forbidden → `moped=no`, unknown → `moped=unverified`; `naviscoot:builtup=yes|no` on NL cycleways/paths. Outside the region OSM is untouched.
- Valhalla 3.9.1 pinned, patched `routing/valhalla/graph.lua`. Moped paths get `max_speed` 30 built-up / 40 outside (edge `speed_limit`); unverified speed 15 (placeholder). **Every motor_scooter request sends `date_time: {"type": 0}`**; level 1/2 `expand_within_distance` = 1,000 km.
- API (`api/`, Fastify 5 + TS): `x-api-key` on everything but `/health`. `POST /route` = Valhalla JSON + top-level `naviscoot` key: stretches with inclusive shared shape indices covering the whole route, `totals_m` summing to `length_m` exactly, and `speed_limits` runs (carriageway 45, paths the edge's 30/40, default 30). `format: osrm` for Ferrostar. Verified-only = `exclude_locations` loop, cap 5. Reports: append-only JSONL.
- Deploy = repo-root `docker-compose.yml` (Valhalla internal, no published port; API behind Coolify's proxy; graph unit bind-mounted read-only at `/repo/routing/build/nl` from `NAVISCOOT_GRAPH_DIR`, default `/data/naviscoot/nl`; reports volume) + `api/Dockerfile` + `routing/deploy-graph.sh`. Steps in `routing/README.md` "Deploy (Coolify)".
- Served unit = `routing/build/nl/` (`tiles.tar`, `valhalla.json`, `admins.sqlite`, `fused_access.csv`). Refresh = `routing/refresh.sh [--force]`, rollback = `routing/refresh.sh rollback`; restart the API after either.
- **iOS** (`ios/`, SwiftUI, iOS 18+, Swift 5 mode, XcodeGen `project.yml` + committed `.xcodeproj` and `Package.resolved`): Ferrostar 0.59.0, swiftui-dsl 0.26.1, MapLibre 6.24.0, all `exactVersion`. Every `xcodebuild` needs `-skipMacroValidation`.
  - API URL/key from gitignored `ios/Config/Local.xcconfig` → Info.plist. `NSAllowsLocalNetworking`. Background modes `audio` + `location`.
  - `RouteParser`: Ferrostar OSRM parser (precision 6) + separate decode of duration and `naviscoot`. Geometry count must equal last `end_shape_index + 1`.
  - Guidance: `FerrostarCore(customRouteProvider:)`. Start uses the preview's plan; the provider only serves reroutes (same `verified_only`). `PlanBook` maps Ferrostar `Route` → `RoutePlan`. Reroutes are accepted by `RideNavigationDelegate` on main: the simulator follows the new route first, then `startNavigation`.
  - Voice: `DutchSpeechSynthesizer` rebuilds every utterance as plain text with the `nl-NL` voice (Valhalla SSML has no language) and records each line. The unverified warning goes through the same `SpokenInstructionObserver`, so mute and audio focus apply.
  - Progress index = step start (joints shared; the arrive step is a degenerate 2-point step) + `currentStepGeometryIndex`.
  - On the simulator rides are simulated by default (`-NaviscootSimulateRide`, `-NaviscootSimSpeedKmh`, `-NaviscootSimOrigin`).
  - All UI strings in `ios/Naviscoot/App/Strings.swift` (English; voice Dutch).
- Simulator UI is driven by XCUITest (`NaviscootUITests` scheme), not idb (idb_companion 1.1.8 can't do HID on Xcode 27).
- No code comments unless the reason is non-obvious. Commits only when the run allows it. `origin` = private https://github.com/roandegraaf/naviscoot; a push needs the user's go-ahead (given once for publishing the repo).

**Commands** (see `data/README.md`, `routing/README.md`, `api/README.md`, `ios/README.md`)
- Refresh `routing/refresh.sh`; `routing/serve.sh start|stop` (8002); `cd api && API_KEY=… npm start` (8080).
- Tests: `cd data && uv run pytest` (50; `-m docker` 6, `-m valhalla` 12); `cd api && npm test` (45); `cd ios && xcodebuild … -scheme Naviscoot test` (31 unit); `-scheme NaviscootUITests test` with `TEST_RUNNER_NAVISCOOT_API_KEY` (3 UI tests, ~3.5 min, needs 8002 + 8080; `SearchAndPreviewUITests` also needs `simctl location set 52.2977646,5.445363`).
- Simulator: `naviscoot-iphone17` (iPhone 17, iOS 27.2 runtime 24B8117), boot headless with `xcrun simctl boot`.

**Key files**
- `data/naviscoot_data/`: `fuse.py`, `rewrite.py`, `valhalla.py`, `paths.py`. `routing/`: `refresh.sh`, `build.sh`, `serve.sh`, `valhalla/graph.lua`, `regression_cases.json`.
- `api/src/`: `app.ts`, `route.ts`, `classify.ts` (incl. `speedLimits`), `reports.ts`, `valhalla.ts`, `config.ts`.
- `ios/Naviscoot/`: `Routing/`, `Search/`, `Preview/`, `Ride/` (`RideModel`, `RideView`, `RideNavigation` [provider, delegate, options, simulator], `RouteProgress`, `DutchSpeech`, `ReportQueue`), `App/`.

**Numbers:** OSM 2026-11-13, NDW 2026-11-14 17:41Z. Fused 72,552 cycle paths (18,988 allowed, 35,758 forbidden, 17,806 unverified). Utrecht Domplein → Amersfoort 22.19 km. UI proof route (case origin → Woudenbergseweg 42 Maarsbergen): 36.11 km with 483 m unverified (way 1497802338, limit 30); verified-only 39.44 km.

## Slice: 1 — repo setup and coverage audit (2026-11-14)
**Shipped**
- Repo layout (`data/ routing/ api/ ios/ docs/` with `.gitkeep`), `.gitignore`, root and data READMEs.
- uv project `naviscoot-data` with the `fetch` and `audit` entry points.
- Coverage audit report and inspection map; hand check of 10 samples.

**Key decisions**
- NDW: per-code API calls rather than the bulk file, because only the API has `lastModifiedOn`.
- Clipping: pure pyosmium rather than osmium-tool. The node pass takes 3 min and the whole clip under 5 min, so no extra system dependency.
- G12b is matched and counted but not used as evidence: a single end sign doesn't say which side is the moped path.
- Each conflict gets a likely cause:
  - "own traffic_sign agrees with NDW": OSM contradicts itself.
  - "neighbour has sign's status": a junction matching artefact.
  - "unexplained".
- Basemap: PDOK BRT grijs, because CARTO now requires an API key and OSM tiles need a referer that `file://` doesn't send.

**Notes / leftovers for fusion**
- NDW resolves 939 km of unknown with point evidence alone. 16,441 unknown ways carry no hint tags at all.
- 85% of NDW bearings are quantised to N/E/S/W, so the bearing test is weak at junctions; the 15% with precise bearings are much more trustworthy.
- Hand check: 10/10 classifications reproduce the raw data.
  - Of the 3 conflicts: 1 junction artefact, 1 genuine disagreement, 1 probably outdated OSM.
  - The "neighbour" label wrongly explains away case 10 (precise NDW bearing, newer than OSM).
- 95 OSM ways contradict themselves (moped tag vs traffic_sign).
- 1,484 signs had no cycle path within 20 m. Only 127 of them are next to a road with `cycleway*=track|lane`; most are near footways and residential roads.
- NDW `conditions.exemptions` never deviate from the sign code (0 cases), so they add nothing. Supplementary signs are common: 3,569 matched signs, e.g. "snorfietsen niet toegestaan", "onleesbaar", OB505, OB502. They are counted, not interpreted.
- The unknown hint tags (`motor_vehicle=no`, `access=no`, `mofa`) were deliberately not used in classification.

**Placeholder choices:** the trust thresholds of the newer-NDW rule (10 m, 20 m, matched only, OB505/OB502 excluded); the Valeriusplein override (now weaker evidence, see above); map colours (conflict magenta, unknown orange, NDW-allowed green dashed, NDW-forbidden blue dashed); sample seed 20261114 and strata 4 allowed / 3 forbidden / 3 conflict; NDW TTL 20 h.

**Runtime-unverified:** none. The map was opened from `file://` in Chrome via DevTools: 27,668 lines and the PDOK tiles load, way and sign popups work, no console errors.

**Open (user):** the first commit. Command in `docs/slides/moped-nav/status/slice-1.md`.


## Slice: 2 — fusion of OSM and NDW (2026-11-14)
**Shipped**
- `data/naviscoot_data/fuse.py`, `model.py`; `audit.py` and `report.py` extended. pytest dev dependency, `data/tests/test_fuse.py` (42 tests).
- `data/overrides.csv` with one real entry; `data/build/fused_access.csv`.
- `coverage.md`: fusion status table, unknown-by-stage table, delta vs slice 1, source breakdown, sign attachment table, OB505/OB502 note, override table, conflict summary. New `docs/audit/conflicts.md`.
- Map: layers for direct and propagated NDW statuses and for the override list; sign popups show the attached way or why a sign is ambiguous.
- Hand check of 5 random propagated ways (5/5 reproduce, direction and junctions checked independently from the pbf) appended to `handcheck.md`.

**Key decisions**
- The slice 1 point-evidence figure is still computed with the unchanged slice 1 matching, so 1,177.9 km stays reproducible.
- Attachment: precise bearings prefer a path within 20°; a cycle junction (≥3 arms) within 8 m makes the sign pick the arm leaving in its travel direction (≤20° precise / ≤45° quantised, beating the next arm by ≥15°), else ambiguous. A sign <5 m before the end of its path is handed to the next path when it is a plain joint.
- Propagation stops at road junctions (motor roads incl. `service` except driveway/parking_aisle; footway/path/track/steps don't stop) and cycle path branches, also partway along a path. On the signed path the scan starts at the sign. A next path with such a junction partway along it is not entered, because status is per whole way. It also stops at dead ends, a next path carrying its own G-sign, a path whose explicit OSM tag says the opposite (that path still gets its conflict row), a same-direction G12b, closed loops, and after 5 km.
- Override entry: hand-check case 10 (Valeriusplein), forbidden as the safe side, marked not surveyed.
  - Its NDW sign turned out to be registered in 2016; the 2025 date was the re-link batch. Under the sign-date rule OSM's 2023 edit is newer.
  - The entry is kept for the user to review, with a corrected reason.
- Newer-NDW rule: see the Current state header. Signs carrying OB505/OB502 are excluded from it.
  - Why: one forbidden → allowed flip was a G12a+OB505 in Nieuwkoop where OSM says G11, the same pattern as hand-check case 8.
- Conflicts are per way (not per sign-way pair as in slice 1); the slice 1 per-pair tables were removed from coverage.md.

**Notes / leftovers**
- Propagation adds only 106 km. Most propagated ways are short bridges, tunnels and segments between two parts of one path; 64% are one hop from the sign. Junctions anywhere along a path stop it, which is deliberate but conservative.
- Bug found by review and fixed in this slice: the first version checked junctions only at path ends. That gave 180 km of propagation, including paths entered across a road crossing partway along them.
- 2,330 ways (62.3 km) resolved by slice 1 are unknown after fusion, mostly because their sign is now ambiguous at a cycle junction.
- Hand-check case 9 (127521919) still attaches to the OSM-allowed way; OSM wins.
- Audit runtime went from 17 s to ~45 s (road-node pass and candidate tracking).
- WKD is still unused; 1,035 km of unknown cycle paths remain and become "unverified" in routing.

**Placeholder choices:** the trust thresholds of the newer-NDW rule (10 m, 20 m, matched only, OB505/OB502 excluded); the Valeriusplein override (now weaker evidence, see above); map colours for the new layers (override black, propagated allowed light green dotted, propagated forbidden light blue dotted); thresholds 8 m junction radius, 5 m hand-over, 15° arm margin, 20° precise tolerance, 5 km propagation cap.

**Runtime-unverified:** none. The map was opened from `file://` in Chrome via the DevTools MCP:
- 27,100 ways and 18,595 signs; all 9 overlays listed (propagated: 362 allowed, 1,515 forbidden).
- Re-checked after the precedence change.
- Way and sign popups work on a propagated way.
- 48/48 PDOK tiles load; no console messages.

## Slice: 3 — routable graph, patched Valhalla, regression suite (2026-11-14)
**Shipped**
- `uv run rewrite` (`data/naviscoot_data/rewrite.py`): writes the NL extract with the fused classes and `naviscoot:builtup`; exits 1 if a CSV way is missing.
  - Unit tests in `data/tests/test_rewrite.py`: allowed/forbidden/unknown, `mofa` grants nothing, zones, spread, a pbf round trip.
- `routing/`: patched `graph.lua` (+ `.patch`), `build.sh`, `serve.sh`, `README.md` (fixes, build figures, search configuration, verified-only results, known gaps).
- Synthetic fixture `routing/test/fixture.osm` (`.gitignore` gets `!routing/test/*.osm`). `test_graph_lua.py` builds it with stock and patched Lua and proves each fix against stock.
- `data/naviscoot_data/valhalla.py` client. Regression suite: `routing/regression_cases.json` + `test_regression_routes.py` (11 cases plus an override-in-extract check), markers `docker`/`valhalla` deselected by default.

**Key decisions**
- `graph.lua` is still the tag transform in 3.9.1 (`mjolnir.graph_lua_name`), so all fixes live in Lua.
- Two fixes beyond the OVERVIEW's three, both in the regression evidence:
  - `motorroad=yes` always closes moped access. Stock only does this via admin country overrides on road class ≤ primary.
  - Bollard, block and cycle_barrier nodes don't close mopeds. Untagged bollards sit on 1,062 allowed moped paths in the region.
- Speeds: carriageway relies on `top_speed` 45. Moped paths get the legal limit as tagged speed; built-up comes from road speed limits around the path.
  - Stock 3.9.1 measured 25 km/h rural / 20 urban on paved cycleways, not the OVERVIEW's 8.
- Long-route fix (found here): stock hierarchy limits expand cycle paths only within 5 km of either end, so Amersfoort → Arnhem/Zwolle/Amsterdam got "No path". Raised to 1,000 km in config.
  - With wide limits the bidirectional A* returned a suboptimal 25.35 km Domplein route. `date_time` type 0 switches to the unidirectional A*, which finds the 22.19 km N237 route. Max 1.1 s for 180 km.
- Regression cases carry a `naive_costing` (bicycle/pedestrian/auto) that must still use the avoided way, so a case that stops tempting a router fails instead of passing silently.
- Against a stock NL graph, 6 of 11 cases fail (override, use_sidepath, mofa, Domplein 27.4 km, G11 edge-walk error, verified-only). The other four (G13, footway, autoweg, motorway) guard regressions.

**Notes / leftovers**
- Verified-only: 11/11 real trips that touched an unverified way converged in 2-4 requests (+0-3.3 km).
  - 5 degenerate 0.2-0.3 km trips along a single unverified way fail ("No path"), because the exclude point hits the snapped origin/destination edge. The API should cap at ~5 requests and fall back to the last route with the stretch labelled unavoidable.
- `motor_vehicle=no` on roads still closes mopeds (C12 is not binding on a bromfiets). This causes detours, not illegal routes.
- Side-tagged cycle tracks can't be separated from the carriageway. Outside the region, untagged and mofa-only cycleways are closed (plain OSM quality).
- The regression run reads `routable.osm.pbf` and the region pbf for the override check (~2 s).

**Placeholder choices:**
- Unverified speed 15 km/h.
- Built-up proxy thresholds: ≤50 urban, ≥60 rural; residential/living_street urban; 8 spread rounds; unset → 30.
- `LOCAL_EXPANSION_M` = 1,000 km.
- Regression case picks: largest detour among the 60 candidates nearest Amersfoort; N701 for use_sidepath (all such roads with a parallel G12a are in Flevoland); random-OD case for verified-only.
- Fixture coordinates and names.

**Runtime-unverified:** none (no UI). All routing behaviour was exercised against the live local NL graph and the fixture graphs.

## Slice: 4 — thin API, local (2026-11-14)
**Shipped**
- `api/`: Fastify 5, TypeScript (strict, ESM), Vitest, `package-lock.json`. `npm run build|typecheck|test|test:integration`, `npm start`.
- `POST /route` (origin, destination, `verified_only`, `format` valhalla|osrm, `language` default nl-NL), `POST /reports`, `GET /reports`, open `GET /health`.
- Classification via edge_walk + `fused_access.csv` in memory; verified-only loop ported from `valhalla.py` (cap 5, fallback with `unavoidable`).
- Tests: 34 unit (fake Valhalla: classification, totals, loop incl. failure/cap/endpoint, auth, errors incl. classification_failed, reports incl. restart and crash-truncated line) and 7 integration (`verified-only-north-south`, OSRM format, Domplein, 422, Groningen → Maastricht 200+ km).
- `api/README.md`; `.gitignore` gets `api/data/`.

**Key decisions**
- Fastify over Hono: built-in JSON-schema validation and `inject()`, no Node adapter. Auth runs in `onRequest`, so a keyless request with a bad body gets 401, not 400.
- Response = Valhalla's own JSON plus a top-level `naviscoot` key. Ferrostar's Valhalla integration only parses the extended OSRM format (confirmed in its docs), so `format: osrm` returns `routes/waypoints/code` at the top level with banner and voice instructions.
- Lengths: Valhalla edge lengths fall 0.02-0.03% short of the route length (8 m on 36 km, 27 m on 129 km). Stretches use edge lengths scaled to the route length with largest-remainder rounding, so totals equal `length_m` exactly. The raw sum is exposed as `edge_length_m`; a gap > 0.5% adds a warning.
- A fourth class `forbidden` (always 0 in practice) plus a warning, so graph/CSV drift is visible instead of being called a moped path.
- `unavoidable`: `endpoint` when an unverified stretch lies only on the first/last edge, `no_alternative` when the loop failed or hit the cap.
- Errors: `422 no_route` only when Valhalla finds no route; `502 classification_failed` when a route exists but its edge walk fails; `502 valhalla_unavailable` when Valhalla is down.
- Reports: append-only JSONL with fsync per write; a crash-truncated last line is dropped at start. Chosen over SQLite (no native module; `node:sqlite` is still experimental on Node 24.14).
- Valhalla service limits were already raised in slice 3 (trace 400 km, 2,000 exclude locations), so long routes edge-walk fine.

**Notes / leftovers**
- Measured live (built server, curl): 401 without/with a wrong key; `verified-only-north-south` 36.25 km with one 483 m unverified stretch (way 1497802338); verified-only 39.54 km, 2 requests, no unverified stretch; report survives a restart.
- For iOS:
  - Ferrostar needs a custom `RouteRequestGenerator` (POST `/route` with `x-api-key` and `format: osrm`).
  - It also needs a response parser that hands the body to the OSRM parser and reads `naviscoot` separately.
  - Ferrostar's `ValhallaExtendedOSRMAnnotation` (speed limits) may need extra Valhalla options (shape attributes / filters) in `valhallaBody` (`api/src/route.ts`). Check this in the iOS slice.
- Only origin + destination (one leg). No via points.
- A point in the North Sea snapped to the Hull–Rotterdam ferry and routed. `motor_scooter` takes ferries; this is not a legality issue.
- The Python regression suite still passes (12/12). Graph, Lua and fusion were not touched.

**Placeholder choices:** header name `x-api-key`; default port 8080; `MAX_VERIFIED_REQUESTS` 5; 0.5% edge-length warning threshold; note ≤ 2,000 chars, `route_id` ≤ 100; default language `nl-NL`; Valhalla uses counted as moped path when the way is not in the CSV (cycleway, path, mountain_bike, footway, sidewalk, pedestrian, pedestrian_crossing, bridleway); Groningen/Maastricht test coordinates.

**Runtime-unverified:** none (no UI). Every endpoint was called on the built server against the live local graph.

## Slice: 5 — one-command data refresh, local (2026-11-14)
**Shipped**
- `routing/refresh.sh`: `[--force]` runs fetch → audit → rewrite → build → serve-staging → gate (regression suite, then API integration) → promote → verify live → finish. `rollback` is the other mode.
  - On failure it names the step, stops the staging container, keeps the rejected build in `nl-next`, warns that `docs/audit/*.md` were rewritten, and logs the failure.
  - It prints a summary line and appends it to `routing/build/refresh.log`, plus a restart warning when an API answers on 8080.
- `data/naviscoot_data/paths.py`: `FUSED_ACCESS_CSV`, `ROUTABLE_PBF` and `REGRESSION_CASES` env overrides; `SERVED_FUSED_CSV`.
  - `test_regression_routes.py` reads the cases file and the CSV from them (default: the served CSV).
  - `api/test/integration.test.ts` honours `REGRESSION_CASES`. Audit prints the real CSV path.
- `api/src/config.ts`: `FUSED_ACCESS_CSV` defaults to `routing/build/nl/fused_access.csv`.
- `routing/build.sh`: `CONCURRENCY` env (default: all cores, as before).
- READMEs: a "Refresh" section with measured timings, the gate proof and rollback in `routing/README.md`; path notes in `data/README.md` and `api/README.md`.

**Key decisions**
- Entry point is `routing/refresh.sh`, next to `build.sh`/`serve.sh`, which it drives through `OUT`/`NAME`/`PORT`; everything it swaps lives in `routing/build/`.
- The graph dir is the unit: the audit writes the CSV straight into `nl-next` and the rewrite writes the pbf there too, so nothing the live graph uses is overwritten before the gate.
  - Consumers default to the served CSV, so a manual `uv run audit` can no longer desync the API.
  - The CSV copy is not in `build.sh`, because the `-m docker` fixture build goes through it.
- `nl-next` drops `tiles/` after the extract. Valhalla serves the tar only, and the gate proves that.
- `valhalla.json` is relocated by rewriting the `/repo/routing/build/nl-next/` prefix to `.../nl/`; the script asserts that no `nl-next` path remains. Rollback needs no rewrite, because both configs say `/nl/`.
- A failure after promote rolls back automatically. The script never kills an API it didn't start; it prints a restart warning instead.
- `--from`/resume flags were left out: an unchanged fetch is seconds, so a plain run costs ~8.5 min.

**Notes / leftovers**
- First failure-proof attempt: `valhalla_build_tiles` was killed with exit 137. Twelve threads plus the live Valhalla (1.7 GB) don't fit the 7.7 GB Docker VM; slice 3 had built with nothing served. Fixed with `CONCURRENCY` (refresh default: half the cores, same 108 s). That failure was also reported loudly, at step `build`, with live untouched.
- Gate proof: a scratch cases file with an impossible Domplein < 15 km case, via `REGRESSION_CASES`. The run exited 1 at `gate: regression suite`. A before/after snapshot of the live container start time, `nl/tiles.tar`, `nl/valhalla.json`, both CSVs and the working pbf was identical, and 8003 was closed.
- Real run: `--force`, 909 s, exit 0. The new graph is on 8002 and both suites pass against it with default paths. `nl-prev` = the slice 3 build (with its `tiles/` dir).
  - **The data wasn't actually newer**: Geofabrik still served the 2026-11-13 extract, and the fresh NDW download fused to a byte-identical CSV. The refresh had nothing to change. The first run against genuinely new OSM data is still to come, and if it trips a case (most likely the 400-600 m unverified assertion), that is a finding to investigate, not a case to loosen.
- Rollback was exercised twice (back to slice 3 and forward again, 12/12 each time) and once more with an API running, which triggered the restart warning.
- The routable pbf is not rolled back; only the override check reads it.
- `docs/audit/*.md` are committed from the real run's audit (paired with the promoted graph); only timestamps changed.

**Placeholder choices:** staging port 8003 and container name `naviscoot-valhalla-next`; build concurrency default half the cores; free-space precheck 6 GB; summary line format; restart warning instead of restarting the API.

**Runtime-unverified:** none (no UI). Every path was exercised on this Mac against real data and the live local graph.

## Slice: 6 — iOS search and route preview, local API (2026-11-14)
**Shipped**
- `ios/`: XcodeGen `project.yml`, committed `Naviscoot.xcodeproj` with `Package.resolved`, `Config/App.xcconfig` + `Local.xcconfig.example` (`Local.xcconfig` gitignored), `README.md`.
- App: PDOK + MapKit search in one merged list → PDOK `lookup` on selection → preview from the current location.
  - Preview: time, distance, arrival, per-class bar and rows from `totals_m`.
  - Map: route drawn per stretch (verified solid blue, unverified dashed orange, forbidden dashed red) on OpenFreeMap.
  - "Verified roads only" toggle re-requests with `verified_only: true`. Tapping the unverified row zooms to those stretches. Start button present but disabled.
- `NaviscootTests` (18 unit): Ferrostar parse of a real OSRM fixture (1,457 points = last shape index + 1), segment split (contiguous, inclusive, ≥2 points, mismatch rejected), totals, all four classes, request shape, error mapping, formatting, PDOK parsing and request, search merge.
- `NaviscootUITests` (1, own scheme): the full search → preview → zoom → verified-only flow, asserting every displayed figure against a direct API call for the same request. Screenshots are written to `SCREENSHOT_DIR`.

**Key decisions**
- Ferrostar now only for parsing; the preview draws with swiftui-dsl directly. For guidance, `NaviscootClient` can back a Ferrostar `RouteProvider.customProvider` (`CustomRouteProvider.getRoutes(userLocation:waypoints:)`), keeping the `naviscoot` metadata.
- Pins: Ferrostar 0.59.0 (2026-10-22) with the swiftui-dsl/MapLibre pair its own demo resolves; 0.27.0 (2026-11-09, MapLibre 7) avoided.
- The search merge interleaves; addresses lead when the query contains a digit; a place with an address's exact name is dropped. PDOK `suggest` is limited to `adres, weg, postcode, woonplaats` and biased with `lat`/`lon`.
- Distances under 1 km show in metres ("483 m"), otherwise one decimal km. Time rounds to minutes, "1 h 11 min" above an hour.
- The UI proof uses Woudenbergseweg 42 Maarsbergen, not the `verified-only-north-south` destination: the nearest address to that coordinate (Maarnse Grindweg 42) routes around the unverified way (0 m). Of 17 nearby addresses tested, the Woudenbergseweg/Scherpenzeelseweg ones keep the 483 m stretch.
- UI driven by XCUITest instead of idb (see header).
- Swift 5 language mode to stay clear of Swift 6 isolation errors around the Ferrostar/MapLibre types; LocationService and models are `@MainActor`.

**Notes / leftovers**
- Measured in the simulator, both matching the API exactly:
  - Default: 1 h 11 min, 36.1 km, carriageway 21.0 km, moped path 14.7 km, unverified 483 m.
  - Verified-only: 1 h 13 min, 39.4 km, 26.6 / 12.9 km, 0 m.
- Screenshots (scratchpad, not committed): `02-search-address`, `03-search-station`, `04-preview-default`, `05-preview-unverified-zoom`, `06-preview-verified-only`.
- Bug found and fixed during the proof: a long result list plus the keyboard pushed the search field under the status bar. The card now caps at its content height and shrinks.
- `xcodebuild -downloadPlatform iOS` installed two iOS 27.2 runtimes (24B8117 and the device-specific 24B91016s), ~16 GB; free disk on the data volume went from 31 GB to 15 GB. The 24B91016s runtime can be removed with `xcrun simctl runtime delete` if space is needed (not done: not mine to delete).
- `npm test` failed once (1 of 41) right after the simulator run and passed 4/4 times after; `api/` was not touched. Treat as a possible timing flake in the integration tests.
- MapKit deprecation: `placemark` is used only below iOS 26 (`location`/`addressRepresentations` above).
- The API was started for this slice with the local key from `ios/Config/Local.xcconfig` and stopped at the end.

**Placeholder choices:** bundle id `nl.naviscoot.app`; OpenFreeMap `liberty` style; colours from the mockup (verified #0B5FD9 solid, unverified #C2410C dashed [1.6, 1.0] line widths, forbidden #B42318 dashed); line width 7 with an 11 white casing; SF Symbols `mappin.and.ellipse` (address), `building.2` (place), `scope`/arrows (zoom hint); PDOK type filter and 8 rows; MapKit region 60 km; merge limit 12; 300 ms search debounce; disabled Start button; copy in `Strings.swift`; skipped the mockup's Favourites/Recent sections; simulator device `naviscoot-iphone17`.

**Runtime-unverified:** none for this slice's scope. Search and preview were exercised in the iOS 27.2 simulator by XCUITest with screenshots inspected; not yet on a real iPhone.

## Slice: 7 — iOS guidance, Dutch voice, reroute, unverified warning, reports (2026-11-14)
**Shipped**
- `ios/Naviscoot/Ride/`. The preview's Start opens a Ferrostar session; the ride screen follows mockup screen 3:
  - Banner: maneuver symbol, distance to the maneuver, street or instruction text.
  - Stretch chip with its limit ("Moped path, limit 40"), a rerouting chip, and Report and Mute buttons.
  - Speed circle and limit sign; the unverified warning chip.
  - Remaining time, distance and arrival, and End (back to search). The screen stays awake during a ride.
- Dutch voice through `DutchSpeechSynthesizer` (see header) and a spoken Dutch warning once per unverified stretch.
- Reroute: Ferrostar's deviation detection → `NaviscootRouteProvider` → `POST /route` with the same `verified_only` → the new plan and its `naviscoot` metadata.
- Reports: `ReportQueue`, persisted in Application Support. It retries with backoff and at app start, and drops 400/413/422. The toast reads "Report saved with your position" or "No connection. Report kept, retrying (n waiting)".
- `RideSimulator` (simulated location provider with a Detour) and launch arguments for simulated rides.
- API: `naviscoot.speed_limits` from `edge.speed_limit` (`classify.ts`, `valhalla.ts`). Tests: 3 unit + 1 live integration. Fixtures refreshed (same geometry, now with `speed_limits`).
- Tests: 13 new unit tests (`RideTests`, `ReportQueueTests`) and the `RideUITests` proof (2 tests). READMEs: `api/` (speed limits), `ios/` (guidance, simulated rides, UI proof).

**Key decisions**
- Built-up for the ride screen comes from a separate API array, not from splitting stretches. Splitting would have changed `first_edge`/`last_edge`, the verified-only exclude points and the `unavoidable` labels. Valhalla already holds the Lua's 30/40 decision as edge `speed_limit` (checked live: cycleway 30 ×33, 40 ×77).
- An own simulator instead of Ferrostar's `SimulatedLocationProvider`. It needs a settable km/h and a sideways detour, and must switch routes before `startNavigation` restarts it. Otherwise it would replay the old route and reroute every 5 s.
- Warning position: shape indices against the step-derived global index plus projection, not Ferrostar's `distanceRemaining`. The fixture proves the step joints (Σ counts − joints = 1,457, plus the 2-point arrive step).
- The warning is spoken through `SpokenInstructionObserver`, not straight to the synthesizer, so audio focus (ducking, background) and Mute apply to it too.
- The speech hook is visible only in simulated rides: a debug panel whose accessibility value is the full log. XCUITest can't read app memory.
- The warning proof starts 1.4 km before the stretch, computed from the API's own geometry. A full 33 km ride would take minutes even at warp. The test first checks that the route from that point still crosses way 1497802338 (Bellman: a suffix of a shortest path stays shortest).

**Notes / leftovers**
- Measured in the simulator:
  - Banner "20 m / Holkerpad".
  - Spoken lines, all `nl-NL`: "Richting het zuiden rijden.", "Over 50 meter, Rechts afslaan.", "Links afslaan naar Holkerpad.", …
  - The report reached `GET /reports` with that `route_id`, the position near Holkerpad and the tap time.
  - Detour → new `route_id`, "reroutes 1", "Richting het westen rijden." spoken, the banner moved on.
  - Warning "Unverified path in 930 m, for 483 m". Spoken: "Let op: over 1 kilometer een onbevestigd fietspad van 500 meter."
  - On the stretch: "On unverified path, 450 m left", chip "Unverified path, limit 30", sign 30. Spoken exactly once; cleared after the stretch.
- Screenshots (scratchpad, not committed): `07-ride-banner-voice` … `11-ride-warning-inside`.
- MapLibre's compass poked out behind the banner corner; it is hidden on the ride screen (logo and attribution stay).
- Skipped from the mockup: the "Then left, 1.2 km" next-maneuver chip. Arrival only shows "You have arrived" in the banner.
- A 30-zone road still shows limit 45 (OVERVIEW rule). `min(45, posted)` would be one line in `edgeLimitKmh` if wanted.
- The local API was started for this slice and stopped at the end; `api/data/reports.jsonl` now holds the proof's reports.

**Placeholder choices:**
- Warning: lead distance 1,000 m (chip and voice); Dutch wording "Let op: over … een onbevestigd fietspad van …" / "u rijdt op een onbevestigd fietspad, nog …"; Dutch distances rounded to 10 m (<100 m), 50 m, then 0.1 km.
- Deviation: 40 m, needing an accuracy of 25 m or better. Steps advance at 30 m before / 5 m after. Waypoint range 100 m.
- Simulator: 0.5 s ticks, default 45 km/h, detour 150 m sideways; proof speeds 120 and 90 km/h.
- Reports: retry delays 10/30/60/120/300 s; 400/413/422 dropped; toast copy; flag icon.
- Maneuver SF Symbols; camera zoom 16.5, pitch 40, rotated to course; puck colours; warning chip #FFF1E7 with #C2410C border; limit sign ring #DC2626.
- End returns to search. Mute also silences the warning. Ride copy in `Strings.swift`.

**Runtime-unverified:** everything on a real iPhone:
- the locked screen and background audio and location (user-gated);
- real GPS deviation behaviour;
- how the `nl-NL` voice actually sounds. Speech was proven by the recording hook, not by ear; the simulator has an nl-NL voice.

### Slice 7, continued: deploy preparation (2026-11-14)
The user approved the deploy (`naviscoot.appj.nl`, server `localhost` on `coolify-personal`, repo on their GitHub).
- **Shipped:**
  - `api/Dockerfile`: node 24 alpine, multi-stage, runs as the `node` user, `/reports` owned by node, healthcheck on `/health`.
  - `api/.dockerignore`.
  - Repo-root `docker-compose.yml`.
  - `routing/deploy-graph.sh`: rsync into `nl-next`, then swap, keeping `nl-prev`.
  - `routing/README.md` "Deploy (Coolify)".
  - Commit fe675c3. The private repo https://github.com/roandegraaf/naviscoot (`master`) is pushed.
- **Verified locally** with the same compose file (separate project, API published on 127.0.0.1:8090 by a scratch override only):
  - `/health` is open; no key or a wrong key gives 401.
  - With the key: 36,255 m, 483 m unverified, 20 speed-limit runs.
  - A report survives an API restart. Valhalla has no published port. The test stack was removed afterwards.
- **Blocked:**
  - Reading the Coolify API token from the Keychain was denied by the permission system (classified as unauthorized access), so no Coolify resource was created and nothing on the server was touched.
  - The graph upload needs SSH to the server; no host or user was given, so it was not attempted.
- **Key decision:** the server keeps `valhalla.json` unchanged by mounting the unit at the path it already names, so local and server units are byte-identical and `refresh.sh` output can be uploaded as is.
- **Incident:** while looking for the Coolify config, a redaction bug printed a bearer token from the SyncUp project's MCP entry in `~/.claude.json` (server coolify.servertj.nl) into the session transcript. It was not used or stored anywhere else. Consider rotating it.
- **Runtime-unverified:** `routing/deploy-graph.sh` against a real server (syntax-checked only); Coolify's proxy, TLS and domain mapping.

