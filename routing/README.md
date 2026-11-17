# routing

Self-hosted Valhalla for bromfiets routing: a patched `graph.lua`, build and serve scripts for Docker,
a synthetic fixture that proves the patches, and the regression cases every graph rebuild must pass.

## Pinned version

- Image `ghcr.io/valhalla/valhalla:3.9.1` (latest release on 2026-11-14, arm64 and amd64), set in `build.sh` and `serve.sh`.
- 3.9.1 still applies its OSM tag transform through `lua/graph.lua`.
  - `src/mjolnir/pbfgraphparser.cc` loads the file named in `mjolnir.graph_lua_name`.
  - Without that setting it falls back to the copy compiled into the binary.
- `build.sh config` points `graph_lua_name` at `routing/valhalla/graph.lua`.

## Patches (`valhalla/graph.lua`, diff against stock in `valhalla/graph.lua.patch`)

| Defect in stock 3.9.1 | Stock, measured on the fixture | Fix |
|---|---|---|
| `moped=use_sidepath` is ignored | the route takes the carriageway | `use_sidepath` → no moped access |
| `mofa` leaks into moped access (`mofa=*`, `oneway:mofa`, `mofa:backward`, barrier nodes) | a cycle path tagged only `mofa=yes` is ridden | every `mofa` reference removed |
| Moped paths are slow | 25 km/h on a paved rural cycleway (the class 7 default) and 20 km/h urban, halved again on rough surfaces | legal limit as edge speed and speed limit: 30 built-up, 40 outside |
| Untagged `barrier=bollard`, `block` or `cycle_barrier` nodes close moped access | the route detours around a moped path with one bollard; 1,062 allowed moped paths in the region carry such a node | a moped passes these like a bicycle; `motorcycle_barrier`, gates, chains and bars still close it |
| Autoweg (`motorroad=yes`) is closed only by the admin-based country override, and only up to road class primary | already avoided on the fixture trunk | `motorroad=yes` always closes moped access |
| `moped=no` is reopened by `motor_vehicle:forward`, `vehicle:backward` and the like, which are read later | a residential street with `moped=no` and `motor_vehicle:forward=yes` is ridden | `naviscoot:override=forbidden` (set by the rewrite step for a forbidden entry in `data/overrides.csv`) always closes moped access |
| Cycleways and paths get road class 7 (service/other), which `motor_scooter` costing weights 0.5, more than primary (0.2); `use_primary=0` triples it | the route takes a 13% longer 30 km/h street over an equally fast moped path | a verified moped path gets road class residential (no class penalty); unverified paths keep class 7 |

- The 8 km/h figure from the OVERVIEW was not observed on paved paths in 3.9.1.
- The bollard fix is a fifth defect, found in this slice: untagged bollards on moped paths are common in NL.
- Speed rules:
  - Carriageway: the `motor_scooter` default `top_speed` of 45 caps every edge.
  - Moped paths: `highway=cycleway|path` with moped access. 30 km/h when `naviscoot:builtup=yes` or unset, 40 km/h when `no`.
- Unverified class:
  - The rewrite step marks a fused-unknown cycle path as `moped=unverified`.
  - Lua grants access and sets the edge speed to `naviscoot_unverified_speed`, while the speed limit stays 30/40.
  - **Placeholder: 15 km/h**, to be tuned against real routes.

## Commands

From the repo root, after `cd data && uv run audit`:

```sh
(cd data && uv run rewrite)       # data/build/routable.osm.pbf: fused classes + naviscoot:builtup
routing/build.sh all              # config, admins, tiles into routing/build/nl (gitignored)
routing/serve.sh start            # valhalla_service on http://127.0.0.1:8002 (stop: routing/serve.sh stop)
(cd data && uv run pytest -m docker)     # fixture: stock vs patched graph.lua, ~8 s
(cd data && uv run pytest -m valhalla)   # regression cases against VALHALLA_URL (default 127.0.0.1:8002), ~2 s
```

`build.sh` reads `OUT`, `PBF`, `GRAPH_LUA` (`stock` for the unpatched script) and `USE_ADMINS`. `serve.sh` reads
`OUT`, `NAME` and `PORT`. The fixture test uses these to build two graphs side by side.

These are the single steps. A manual `build.sh all` into `routing/build/nl` does not copy `fused_access.csv` next to
the tiles; use `refresh.sh` below to replace the served graph.

## Refresh (one command)

```sh
routing/refresh.sh            # fetch (incremental), audit, rewrite, build, gate, promote
routing/refresh.sh --force    # same, but re-download OSM and NDW
routing/refresh.sh rollback   # swap the previous build back in and restart Valhalla
```

It lives in `routing/` next to `build.sh` and `serve.sh`, which it drives through the same `OUT`, `NAME` and `PORT`
variables, and everything it produces and swaps lives in `routing/build/`.

**The served unit.** `routing/build/nl/` holds `tiles.tar`, `valhalla.json`, `admins.sqlite` and the
`fused_access.csv` the tiles were built from. The API (`FUSED_ACCESS_CSV`) and the regression suite read that CSV by
default, so the graph and its classification always move together. `data/build/fused_access.csv` and
`routable.osm.pbf` are working copies. After a promote or rollback they are synced, so a manual `uv run rewrite`
starts from the served data.

**Steps.** A failure at any step exits non-zero with `refresh FAILED at step '<name>'`, stops the staging container
and leaves `routing/build/nl`, its CSV and port 8002 untouched.

1. `fetch`: `uv run fetch [--force]`.
2. `audit`: writes the fused CSV straight into `routing/build/nl-next/`.
3. `rewrite`: writes `nl-next/routable.osm.pbf`.
4. `build`: `build.sh all` with `OUT=routing/build/nl-next`, then drops the `tiles/` directory. Valhalla serves
   `tiles.tar` only.
5. `serve-staging`: serves `nl-next` as container `naviscoot-valhalla-next` on port 8003 (`STAGE_PORT`).
6. `gate: regression suite`: `uv run pytest -m valhalla` against 8003 with the staged CSV and pbf.
7. `gate: api integration`: `npm run test:integration` (`REQUIRE_VALHALLA=1`) against 8003 with the staged CSV.
8. `promote`: `nl` → `nl-prev` (the older `nl-prev` is deleted), `nl-next` → `nl`. The `/repo/routing/build/nl-next/`
   paths in `valhalla.json` are rewritten to `.../nl/`, and Valhalla on 8002 is restarted.
9. `verify live graph`: both suites again against 8002, with default paths. A failure here rolls back
   automatically.
10. `finish`: moves the routable pbf to `data/build/` and copies the CSV to `data/build/`.

The script then prints a one-line summary and appends it to `routing/build/refresh.log`. The summary has the OSM and
NDW dates, the fused counts, the tile size, test counts and the time per step. Failures are logged there too. If an
API answers on `API_PORT` (8080), the script tells you to restart it: it holds the old CSV in memory, and the script
doesn't kill a process it didn't start.

**Rollback.** `routing/refresh.sh rollback` swaps `nl` and `nl-prev` and restarts Valhalla. Both configs already
point at `.../nl/`, so nothing is rewritten. Running it twice undoes it. The routable pbf is not rolled back, because
only the override check in the regression suite reads it.

**Things to know**
- The audit rewrites the tracked `docs/audit/coverage.md` and `conflicts.md` on every run, including failed ones.
  Commit them only after a successful refresh; after a failed one, `git diff docs/audit` shows what the new data
  would change.
- A regression case that fails because OSM or NDW changed is a finding to investigate, not a case to loosen.
- `REGRESSION_CASES=<file>` swaps the cases file for the gate, and `GRAPH_LUA=stock` builds with stock Lua. Both
  are for proving the gate.
- Disk: each build dir is about 0.93 GB (tar, admins, CSV) and the staged pbf 1.4 GB. The script wants 6 GB free.

**Measured 2026-11-14** (`routing/refresh.sh --force`, 909 s end to end, exit 0)

| Step | Time | Notes |
|---|---|---|
| fetch | 403 s | 1,411 MB OSM download (the same 2026-11-13 Geofabrik extract), re-clip 281 s, all four NDW codes re-downloaded |
| audit | 45 s | 18,988 allowed, 35,758 forbidden, 17,806 unknown; identical to the slice 2 fusion, because the data hadn't changed |
| rewrite | 340 s | |
| build | 108 s | 6 threads; `tiles.tar` 949 MB (10^6 bytes) |
| serve-staging, gate | 7 s | regression 12 passed, API integration 7 passed |
| promote, verify, finish | 6 s | Valhalla on 8002 is down for about a second while it restarts |

- Without `--force`, fetch is a few seconds when Geofabrik has no new file and NDW is younger than 20 h, so a run takes about 8.5 min.
- The build runs with half the cores (`CONCURRENCY`, default 6 here). With all 12 threads next to the live Valhalla (1.7 GB resident),
  the Docker VM (7.7 GB) killed `valhalla_build_tiles` with exit 137. Six threads take the same time.
- Gate proof: a copy of the cases file with an extra case requiring Domplein → Amersfoort under 15 km, passed as `REGRESSION_CASES`.
  - The run failed at `gate: regression suite` (exit 1, `assert 22.194 < 15`).
  - Afterwards the live container's start time, `nl/tiles.tar`, `nl/valhalla.json` and both fused CSVs were byte-identical, and no
    staging container was left.
- Rollback was run twice: it went back to the slice 3 build and then forward again, with 12/12 regression cases passing on each.

## Deploy (Coolify)

The server only serves. The graph is built here (`routing/refresh.sh`) and published as a GitHub release of this repo;
the stack downloads it at start. The API is built from `api/Dockerfile`. `docker-compose.yaml` in the repo root (Coolify's default compose location) holds:
- `graph`: a one-shot init container (`routing/graph-fetch/`). It downloads `SHA256SUMS` from `GRAPH_BASE_URL`.
  - If the unit on the `naviscoot-graph` volume already matches, it exits at once.
  - Otherwise it downloads `tiles.tar`, `valhalla.json`, `admins.sqlite` and `fused_access.csv` (918 MB) into `nl-next`,
    verifies every checksum and swaps the directory to `nl`.
  - It first logs the host's available memory and free disk. It refuses to download below 2,048 MB available memory or
    2,560 MB free disk (`MIN_MEM_AVAILABLE_MB`, `MIN_DISK_FREE_MB`).
  - Any failure exits non-zero, and then neither Valhalla nor the API starts.
- `valhalla` (3.9.1, memory limit 2 GB): no published port. Only the API reaches it, over the compose network.
- `api`: listens on 8080 inside the network. Coolify's Traefik publishes it through the labels in the compose file: an
  `http` router for `Host(naviscoot.appj.nl)` to container port 8080. The labels stand in for a Coolify per-service
  domain because the Coolify MCP can't set `docker_compose_domains`. The hostname is literal: Coolify escapes `$` in
  labels, so a variable there would never be interpolated.
- Both `valhalla` and `api` mount the volume read-only at `/repo/routing/build`. `valhalla.json` names
  `/repo/routing/build/nl/...`, so the config needs no rewrite and local and served units are byte-identical.
- Reports go to the named volume `naviscoot-reports`.

| Variable | Value |
|---|---|
| `API_KEY` | required; a long random key, kept only in Coolify (runtime). The app's `Local.xcconfig` sends the same key |
| `GRAPH_BASE_URL` | required; `https://github.com/roandegraaf/naviscoot/releases/download/<tag>` |

**Publishing a graph** (one unit = one release tag):
1. Run `routing/refresh.sh`. Its regression gate must pass.
2. Run `routing/publish-graph.sh [tag]`, which needs `gh` logged in. It writes `SHA256SUMS` and creates the release with
   the four files; the default tag is `graph-<UTC date-time>`. The release notes carry the ODbL attribution.
3. In Coolify, set `GRAPH_BASE_URL` to the new tag and redeploy. Rolling back means pointing it at the previous tag and
   redeploying, which downloads that unit again.

Live: `https://naviscoot.appj.nl` on `coolify-personal`, server `localhost`, Coolify project "Naviscoot". `*.appj.nl` is
proxied by Cloudflare, which terminates TLS and talks plain HTTP to the server. That's why the router uses the `http`
entrypoint, like the `http://` domains of the other apps there.

Check with:
```sh
curl -s https://naviscoot.appj.nl/health                                                  # open
curl -s -o /dev/null -w '%{http_code}\n' -X POST https://naviscoot.appj.nl/route            # 401
curl -s -H "x-api-key: $API_KEY" -H 'content-type: application/json' https://naviscoot.appj.nl/route \
  -d '{"origin":{"lat":52.2977646,"lon":5.445363},"destination":{"lat":52.0464515,"lon":5.4059619}}'   # a route
```

Measured locally with the same compose file (graph served over HTTP the way a release is; API port published only for
the test):
- The first start downloads and verifies the unit. A restart downloads nothing, and reports survive it.
- A checksum mismatch, or a memory or disk gate below its threshold, stops the stack before Valhalla starts.
- `/health` is ok; without a key or with a wrong key the API answers 401.
- With the key, the `verified-only-north-south` route is 36,254 m with 483 m unverified.
- Idle memory: Valhalla 83 MB, API 53 MB. Valhalla grew to 1.7 GB while serving locally in slice 5.

## Licence of the data

The graph unit is a derivative of OpenStreetMap: © OpenStreetMap contributors, Open Database License (ODbL),
https://www.openstreetmap.org/copyright. It also uses NDW verkeersborden (CC0).

## Rewrite step (`data/naviscoot_data/rewrite.py`)

- Cycle paths in `fused_access.csv` are rewritten as follows:
  - allowed → `moped=designated`;
  - forbidden → `moped=no`, and `moped:forward`, `moped:backward` and `oneway:moped` are dropped so that nothing reopens a direction;
  - unknown → `moped=unverified`.
- Every `highway=cycleway|path` in NL gets `naviscoot:builtup=yes|no` when it can be derived. The derivation:
  - The path's own `zone:traffic` tag is used first.
  - Otherwise, the path's nodes are compared with road nodes. A road counts as built-up area when its limit is ≤ 50, `NL:urban`, residential or living_street; as outside when its limit is ≥ 60 or `NL:rural`.
  - Paths with no road contact take the majority label of connected paths, for up to 8 rounds.
- Outside the region OSM is left as is. Untagged and `mofa`-only cycleways there are closed to mopeds, which is plain OSM quality but differs from stock (stock opened `mofa` ones).

## Build figures

Measured 2026-11-14 on this Mac:
- Docker VM: 8.3 GB RAM, 12 threads.
- Inputs: Geofabrik NL extract of 2026-11-13 (1.41 GB) and the fusion of slice 2.

| Step | Command | Time | Output |
|---|---|---|---|
| Rewrite | `cd data && uv run rewrite` | 329 s | `data/build/routable.osm.pbf`, 1.4 GB; 72,552 cycle paths classed (18,988 allowed, 35,758 forbidden, 17,806 unverified) |
| Admins | `routing/build.sh admins` | 6 s | `admins.sqlite`, 9 MB |
| Tiles | `routing/build.sh tiles` | 101 s | 228 tiles: `tiles/` 960 MB, `tiles.tar` 912 MB (served) |

`naviscoot:builtup` for all NL paths: 273,223 yes, 108,839 no, 120,899 unset. Of the paths a moped may use in the
region, only 170 designated and 1,025 unverified ones stay unset and fall back to 30 km/h.

## Search configuration (required)

Two settings are needed or long routes fail or come out wrong. The API slice must keep both.

1. **Hierarchy limits.**
   - By default Valhalla expands local roads (level 2, which holds every cycle path and residential street) only within 5 km of either end, and level 1 within 20 km.
   - Moped routes need cycle paths mid-route wherever the main road is closed to them (`use_sidepath`, autoweg).
   - With the defaults, Amersfoort to Arnhem, Apeldoorn, Amsterdam or Zwolle returned "No path".
   - `build.sh config` therefore sets `thor.*.hierarchy_limits.expand_within_distance` for levels 1 and 2 to 1,000 km (`LOCAL_EXPANSION_M`).
2. **`date_time: {"type": 0}` on every `motor_scooter` route request.** This makes Valhalla use the unidirectional time-dependent A*.
   - With wide limits, the default bidirectional A* gave Utrecht Domplein to Amersfoort as 25.35 km (cost 5,343).
   - The time-dependent search returns the cheaper 22.19 km N237 route (cost 5,135). The bidirectional result is not optimal: forcing it along the 22 km path costs 5,155.
   - Queries take 0.1 s locally and up to 1.1 s for 180 km (Amersfoort to Maastricht).
   - `costing_options.disable_hierarchy_pruning` is parsed but ignored in 3.9.1.

## Route classification for the API

Valhalla does not return custom tags. `trace_attributes` with `shape_match: edge_walk` on a route's shape and the
filter `edge.way_id` returns the OSM way id of every edge. Looking those ids up in `fused_access.csv` gives the class.
This is confirmed against the local graph; `data/naviscoot_data/valhalla.py` does it in `Valhalla.route`.

## Verified-only alternative

Mechanism (`verified_only_route` in `data/naviscoot_data/valhalla.py`):
1. Route.
2. Edge-walk the result.
3. Add an `exclude_locations` point at the midpoint of every unverified edge except the first and last edge (the rider starts or ends there).
4. Re-request, until no unverified edge remains.

Validated 2026-11-14 on 37 routes, inside the region and up to 130 km long:
- 40 random origin-destination pairs between 5 and 30 km apart in the region, of which 29 routed.
- 8 trips from one end to the other of an unknown `mofa=yes` path.

| Result | Routes |
|---|---|
| Default route has no unverified edge | 18 |
| Converged after 2 requests | 9 |
| Converged after 3 requests | 2 |
| Converged after 4 requests | 1 |
| Converged after 1 request (unverified only on the end edges) | 2 |
| No path | 5 |

- **It converges for every realistic trip.** All 11 random trips that touched an unverified way converged in at most 4 requests.
  - The verified route was 0 to 3.3 km longer and up to 3 minutes slower.
  - Some came out shorter but slower, because the penalty's cost differs from distance.
- **It fails only on degenerate 0.2-0.3 km trips** that run along a single unverified way. There, an exclude point lands on the edge the origin or destination snaps to.
- Recommendation for the API: run the loop with a cap of about 5 requests. When a request fails, return the last successful route and label its remaining unverified stretch as unavoidable. A second costing or a separate graph is not needed.
- `verified-only-north-south` in the regression suite keeps one real case (a 36 km trip crossing a 483 m unverified path; 2 requests).

## Regression suite

`regression_cases.json` holds real cases taken from the data. `data/tests/test_regression_routes.py` runs them
(`uv run pytest -m valhalla`, non-zero exit on any failure). Case kinds:

- `route`: `avoid_way_ids` must not appear, `use_way_ids` must appear, optional length bounds.
  A `naive_costing` (bicycle, pedestrian or auto) must still use the avoided ways, so a case that stops tempting a
  router is reported instead of passing silently.
- `match`: the way is map-matched with `motor_scooter` and must carry the expected edge speed.
- `verified_only`: the verified-only route contains no unverified way within `max_requests` requests.

Against a stock 3.9.1 graph built from plain OSM, with the same search configuration, 6 of 11 route cases fail:
- the Valeriusplein override is ridden;
- the N701 carriageway is used despite `use_sidepath`;
- the `mofa` path counts as allowed at 20 km/h;
- Domplein to Amersfoort is 27.4 km and leaves the N237 paths;
- Malesluispad errors;
- the verified-only case no longer crosses an unverified way.

The G13, footway, autoweg and motorway cases already pass on stock, because plain OSM tags close those. They guard
against regressions. The 42.6 km stock figure in the OVERVIEW came from a different setup; this stock build gives
27.4 km.

## Known gaps

- `motor_vehicle=no` on a road still closes it to mopeds (stock behaviour). Under the RVV, C12 does not bind a bromfiets, but OSM's `motor_vehicle` includes mopeds. This only causes detours, never an illegal route.
- Side-tagged cycle tracks (`cycleway:right=track` on the road, no separate way) cannot be routed separately from the carriageway.
- Built-up detection is a proxy based on road speed limits, not the official bebouwde-kom boundary.
