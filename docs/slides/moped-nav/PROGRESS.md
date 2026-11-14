# Progress — moped-nav

## Current state
**Slices done:** 1 (audit), 2 (fusion), 3 (routing graph + regression), 4 (thin API, local only). Commits: 0423a8b (slices 1-2), 0773b35 (slice 3), slice 4 on top. `docs/audit/*.md` is committed; `docs/audit/map.html`, `docs/slides/*/status/` and `api/data/` are gitignored.

**Invariants in force**
- Region = 50 km around 52.156, 5.387. Cycle path = OSM `highway=cycleway`; status per whole way. `mofa=*` is never moped evidence, anywhere (fusion, rewrite, Lua).
- Precedence: `data/overrides.csv` > NDW newer and unambiguous > explicit OSM tag > NDW direct > NDW propagated > unknown. The user still has to review the 5 forbidden → allowed flips and the Valeriusplein override (`docs/audit/conflicts.md`).
- Rewrite: allowed → `moped=designated`, forbidden → `moped=no` (drops `moped:forward/backward`, `oneway:moped`), unknown → `moped=unverified`. Every NL cycleway/path also gets `naviscoot:builtup=yes|no` (road-speed proxy + network spread). Outside the region OSM is untouched; untagged cycleways there stay closed.
- Valhalla 3.9.1 pinned, patched `routing/valhalla/graph.lua`:
  - `use_sidepath` closes; no `mofa`; `motorroad=yes` closes; bollard/block/cycle_barrier pass mopeds.
  - Moped paths: speed limit and speed 30 built-up / 40 outside. Unverified paths: speed 15 (placeholder), limit 30/40.
- **Every motor_scooter route request sends `date_time: {"type": 0}`** (unidirectional A*). The server config raises level 1/2 `expand_within_distance` to 1,000 km. Without both, long routes fail ("No path") or are suboptimal. See `routing/README.md`.
- Route classification = `trace_attributes` edge_walk with `edge.way_id`, looked up in `fused_access.csv` (confirmed).
- Verified-only = re-request with `exclude_locations` at unverified edge midpoints, first/last edge exempt. 2-4 requests on real trips. The API caps at 5 and falls back to the last route with `unavoidable` stretches; it never errors when a route exists.
- API (`api/`, Fastify 5 + TS + Vitest): `x-api-key` on everything but `/health` (checked in `onRequest`, before validation). `POST /route` returns Valhalla's response unchanged plus a top-level `naviscoot` key (stretches, `totals_m`, `verified_only`). `format: osrm` = Ferrostar's format. Totals sum exactly to the route length (edge lengths scaled, largest-remainder rounding). Reports: append-only JSONL at `REPORTS_PATH`.
- No code comments unless the reason is non-obvious. No pushes by agents; commits only when the run allows it.

**Commands** (see `data/README.md`, `routing/README.md`)
- `cd data`: `uv run fetch`, `uv run audit` (~45 s), `uv run rewrite` (~330 s → `build/routable.osm.pbf`).
- `routing/build.sh all` (~110 s: config, admins, tiles → `routing/build/nl/`), `routing/serve.sh start|stop` (127.0.0.1:8002).
- Tests from `data/`:
  - `uv run pytest`: 50 unit tests.
  - `-m docker`: 6 fixture tests, stock vs patched Lua.
  - `-m valhalla`: 12 regression tests against the served NL graph.
- `cd api`: `npm ci`, `npm run build`, `API_KEY=… npm start` (127.0.0.1:8080), `npm test` (34 unit + 7 integration, integration skipped without Valhalla), `npm run test:integration` (`REQUIRE_VALHALLA=1`).

**Key files**
- `data/naviscoot_data/`:
  - `fuse.py` (precedence), `rewrite.py` (tags + builtup);
  - `valhalla.py` (client, edge_walk way ids, map_match, `verified_only_route`).
- `routing/valhalla/graph.lua` + `graph.lua.patch` (diff vs stock), `routing/build.sh`, `routing/serve.sh`.
- `routing/test/fixture.osm` (6 synthetic scenes), `routing/regression_cases.json` (11 real cases).
- Tests: `data/tests/test_graph_lua.py`, `test_regression_routes.py`, `test_rewrite.py`.
- `api/src/`: `app.ts` (routes, auth, errors), `route.ts` (Valhalla body, verified-only loop), `classify.ts`, `reports.ts`, `valhalla.ts`, `config.ts`; `api/test/` (fake Valhalla, unit, `integration.test.ts`). `api/README.md` documents endpoints and env vars.

**Numbers:** OSM 2026-11-13, NDW 2026-11-14.
- Fused: 72,552 cycle paths (18,988 allowed, 35,758 forbidden, 17,806 unverified).
- Tiles: 912 MB tar, 228 tiles.
- Utrecht Domplein → Amersfoort: 22.19 km, 36.5 min.

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

