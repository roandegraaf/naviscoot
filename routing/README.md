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
