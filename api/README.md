# api

Thin TypeScript service in front of the local Valhalla. It routes a bromfiets with `motor_scooter`, classifies every
stretch of the route as carriageway, moped path or unverified, offers a "verified roads only" alternative, and stores
"data is wrong here" reports. Valhalla itself stays private; only this service is meant to be exposed.

## Stack

- **Fastify 5**: JSON-schema validation on every body, `inject()` for in-process tests without opening a port, and an
  `onRequest` hook so the API key is checked before any body is parsed or validated. Hono would work too, but on Node
  it needs an adapter and has no built-in schema validation.
- TypeScript (`tsc`, ESM, strict), Vitest for tests, npm with `package-lock.json`. Node ≥ 22 (built on 24).

## Run

```sh
cd api
npm ci
npm run build
API_KEY=change-me npm start            # http://127.0.0.1:8080
```

Valhalla must be up first (`routing/serve.sh start`), and `routing/build/nl/fused_access.csv` must exist. That is the
copy the served graph was built from; `routing/refresh.sh` puts it there (see `routing/README.md`, "Refresh").
The API reads it only at start, so restart the API after a refresh or rollback.

| Env var | Default | Meaning |
|---|---|---|
| `API_KEY` | required | Static key every request except `/health` must send in `x-api-key`. The server refuses to start without it. |
| `VALHALLA_URL` | `http://127.0.0.1:8002` | Valhalla service. |
| `FUSED_ACCESS_CSV` | `../routing/build/nl/fused_access.csv` | Fused cycle path statuses, loaded into memory at start (72,552 ways). |
| `REPORTS_PATH` | `api/data/reports.jsonl` | Report store (gitignored directory). |
| `HOST` / `PORT` | `127.0.0.1` / `8080` | Listen address. |
| `MAX_VERIFIED_REQUESTS` | `5` | Cap on Valhalla requests for one verified-only route. |

## Tests

```sh
npm run typecheck
npm test                    # unit tests (mocked Valhalla) + integration tests, skipped when no Valhalla answers
npm run test:integration    # integration only; REQUIRE_VALHALLA=1 turns a missing Valhalla into a failure
```

The integration tests use the served NL graph, its `fused_access.csv` and cases from
`routing/regression_cases.json`. `VALHALLA_URL`, `FUSED_ACCESS_CSV` and `REGRESSION_CASES` override these; the refresh
gate uses them to test a staged graph.

## Endpoints

Every endpoint except `GET /health` needs the header `x-api-key: <API_KEY>`. A missing or wrong key gets `401
{"error":"unauthorized"}`, also on unknown paths and before body validation.

### `GET /health`

`{"status":"ok","valhalla":true|false}`. Open, for uptime checks.

### `POST /route`

```json
{
  "origin": {"lat": 52.2977646, "lon": 5.445363},
  "destination": {"lat": 52.0464515, "lon": 5.4059619},
  "verified_only": false,
  "format": "valhalla",
  "language": "nl-NL",
  "waypoints": [{"lat": 52.2, "lon": 5.42}],
  "alternatives": 0,
  "depart_at": "2026-11-16T08:00:00+01:00",
  "avoid": {"ferries": false, "unpaved": false, "main_roads": false}
}
```

Only `origin` and `destination` are required. A request with just those two behaves exactly as before the optional
fields existed: the same Valhalla request, and a response equal to the old one apart from the random `route_id`
(compared on every two-point regression case, in both formats, with and without verified-only).

| Field | Default | Meaning |
|---|---|---|
| `verified_only` | `false` | See "Verified only". Applies to every returned route. |
| `format` | `valhalla` | `valhalla` (native JSON, `trip.legs[i].shape`) or `osrm` (Valhalla's extended OSRM format with banner and voice instructions, `routes[i].geometry`). Ferrostar's Valhalla integration only parses the OSRM format, so the iOS app uses `osrm`. |
| `language` | `nl-NL` | Valhalla narrative language. |
| `waypoints` | none | Ordered intermediate stops, at most 8, sent to Valhalla as `break` locations. See "Multi-stop routes". |
| `alternatives` | `0` | Extra routes to return, 0 to 2. Two-point trips only. See "Alternatives". |
| `depart_at` | now | ISO 8601 date-time with offset. Valhalla `date_time` type 1. |
| `arrive_by` | none | ISO 8601 date-time with offset. Valhalla `date_time` type 2. Also works with waypoints (verified on 3.9.1). |
| `avoid.ferries` | `false` | `motor_scooter.use_ferry: 0`: the maximum ferry penalty and 10× ferry cost. Soft: a ferry that is the only way stays in. |
| `avoid.main_roads` | `false` | The quiet profile (see "Quiet profile"). Soft: a main road that is the only way stays in. |
| `avoid.unpaved` | `false` | Done by this service, not by Valhalla. See "Avoid unpaved". |

- The server always sends `costing: motor_scooter`. Without a time it sends `date_time: {"type": 0}` (see
  `routing/README.md`, "Search configuration"); `depart_at` and `arrive_by` replace that with type 1 or 2, so the
  primary route always comes from the time-dependent search.
- Valhalla wants a wall-clock time (`YYYY-MM-DDThh:mm`) local to the trip. The service converts the ISO instant to
  `Europe/Amsterdam` explicitly, independent of the process time zone, so a UTC container sends the right local time
  across daylight-saving changes.
- The served graph carries no time-zone data: Valhalla's own "current time" (type 0) is UTC, an hour behind
  Amsterdam in winter. That only matters for time-conditional access, and it's unchanged from before.
- Unknown properties are dropped silently (Fastify's default `removeAdditional`), at the top level and in `avoid`.
- The response is Valhalla's own response plus one extra top-level key `naviscoot`. It is unchanged for a plain
  two-point request; alternatives add routes to it (see below):

```json
{
  "trip": {"...": "native Valhalla, or routes/waypoints/code for format osrm"},
  "naviscoot": {
    "route_id": "uuid",
    "profile": "fastest",
    "format": "valhalla",
    "length_m": 36254,
    "edge_length_m": 36246,
    "totals_m": {"carriageway": 20961, "moped_path": 14810, "unverified": 483, "forbidden": 0},
    "main_road_m": 8120,
    "stretches": [
      {"class": "unverified", "start_shape_index": 1341, "end_shape_index": 1377, "first_edge": 412, "last_edge": 413,
       "length_m": 483, "way_ids": [1497802338]}
    ],
    "speed_limits": [
      {"start_shape_index": 0, "end_shape_index": 48, "kmh": 45},
      {"start_shape_index": 48, "end_shape_index": 61, "kmh": 40}
    ],
    "warnings": []
  }
}
```

The example is the default route of `verified-only-north-south`. With `verified_only: true` the same trip comes back as
39.54 km with no unverified stretch and `"verified_only": {"requests": 2, "excluded_points": 2, "converged": true}`.

Errors:
- `400`: invalid body (Fastify's validation error, `"error": "Bad Request"`), for example `alternatives` above 2 or a
  time that isn't ISO 8601.
- `400 {"error":"too_many_waypoints"}`: more than 8 waypoints.
- `400 {"error":"conflicting_times"}`: both `depart_at` and `arrive_by`.
- `400 {"error":"alternatives_need_two_points"}`: `alternatives` above 0 together with waypoints. Valhalla only
  computes alternates for a trip without via points (verified on 3.9.1: it silently returns none).
- `422 {"error":"no_route"}`: Valhalla finds no route.
- `502 {"error":"valhalla_unavailable"}`: Valhalla is unreachable or answers 5xx.
- `502 {"error":"classification_failed"}`: a route exists but its edge walk failed, so it can't be classified.

### Classification

1. `trace_attributes` with `shape_match: edge_walk` on the returned geometry gives every edge's OSM way id, length, use
   and shape indices.
2. Per edge: fused `unknown` → `unverified`; fused `allowed` → `moped_path`; any other edge whose Valhalla use is a
   cycleway, path, footway or similar → `moped_path`; everything else → `carriageway`.
   - A way that `fused_access.csv` marks `forbidden` should never be routable. If one shows up it is classed `forbidden`
     and a warning is added: the graph and the CSV have drifted.
3. Consecutive edges of one class merge into a stretch. Shape indices point into the returned geometry
   (`routes[i].geometry`, or the joined `trip.legs[*].shape`, both polyline6; see "Multi-stop routes").
4. **Lengths add up exactly.** Valhalla's edge lengths are rounded to whole metres and sum to slightly less than the
   route length (measured: 8 m short on 36 km, 27 m on 129 km, at most 0.03%). Stretch lengths are the edge lengths
   scaled to the route length and rounded with the largest-remainder method, so `totals_m` and the stretches sum to
   `length_m` (the route length rounded to whole metres) with zero tolerance. The raw sum stays visible as
   `edge_length_m`; a gap over 0.5% adds a warning.

### Speed limits

`speed_limits` holds runs of one legal bromfiets limit, in the same shape indices as the stretches and covering the whole
route. It is independent of the stretches, so it never changes their edges or the verified-only loop.
- Carriageway edges: 45 (OVERVIEW: 45 on the carriageway, also on a road whose own limit is lower).
- Every other edge: the edge's `speed_limit` from `trace_attributes`. The patched `graph.lua` writes the built-up decision into
  it (30 in the built-up area, 40 outside), also on unverified paths. A missing value or anything other than 30/40 gives 30.

### Verified only

With `verified_only: true`:
1. Route and classify.
2. Put an `exclude_locations` point at the midpoint of every unverified edge except the route's first and last edge
   (the rider starts or ends there), keeping the points of earlier rounds.
3. Re-request, up to `MAX_VERIFIED_REQUESTS` requests in total.

The loop never turns an existing route into an error. When a re-request fails or the cap is reached, the last successful
route is returned and every remaining unverified stretch carries `"unavoidable": "no_alternative"`. An unverified stretch
that lies only on the first or last edge carries `"unavoidable": "endpoint"`. `verified_only` reports the number of
requests, exclude points, whether it converged and, if not, `stopped_because`.

### Multi-stop routes

With `waypoints` the route has one leg per stop plus one. **All shape indices (stretches, speed limits, legs) use one
index space: the whole route's geometry.**
- In the OSRM format that is `routes[0].geometry` itself. Valhalla joins the legs there and drops each leg's first
  point, because it repeats the previous leg's last point. The iOS app, via Ferrostar, already uses that geometry.
- In the native format it is the legs' `shape`s joined the same way (leg 2 without its first point, and so on). The
  native response itself is unchanged.
- `naviscoot.legs` lists each leg, in order, as `{start_shape_index, end_shape_index, first_edge, last_edge}`. One leg
  ends where the next starts. It is only present when there are waypoints.
- Each leg is edge-walked on its own and the indices are shifted into the joined space. One edge walk over the
  whole geometry fails at a stop: measured on a trip that turns around at its stop, Valhalla answers "edge_walk
  algorithm failed to find exact route match".
- In the OSRM format, each leg's own shape is rebuilt from its steps: the step geometries joined, without the final
  arrive step, which is a 2-point line on one spot. The route geometry can't simply be sliced, because Valhalla drops
  the first point of every later leg even when it differs from the previous leg's last point. Measured with the same
  stop given twice: Valhalla snaps the two copies about 470 m apart and puts a zero-length leg between them.
- The legs' point counts must add up to the route geometry (`1 + Σ (points − 1)`), otherwise the request fails with
  `classification_failed`, so it never guesses.
- A leg with distance 0 (a repeated stop) isn't edge-walked and has no edges (`last_edge` = `first_edge − 1`).
- A stretch or speed-limit run may span a stop.
- Verified-only treats the first and last edge of every leg as an endpoint, because the rider has to reach the stop.

Measured: Domplein → two stops → Amersfoort, legs at shape indices 0–338, 338–707, 707–955 of a 956-point geometry.

### Fastest guard

`motor_scooter` cost is not time. `speed_penalty_factor` (0.05 per km/h above the 45 km/h top speed, so +0.75 on a
60 km/h road), road-class factors, density and turn costs can make the default pick a route minutes slower than
another costing finds. Measured on 53 Dutch trips of 3-30 km on 2026-11-17, the default alone was up to 12 min slower
than the quickest costing.

- `server.ts` passes `FASTEST_CANDIDATES` (`route.ts`): four costings (`speed_penalty_factor: 0`, with and without
  `use_primary: 1`, `shortest`, and one that also drops the living-street and service penalties).
- For the fastest profile's primary route, they are probed (native format, `directions_type: none`, no exclusions)
  while the default is planned as usual.
- The default stays unless the quickest probe beats it by more than `fastestSlackS()`: 10% of the quickest time, at
  least 30 s and at most 3 min (`FASTEST_SLACK`). That is the price of the smoother route, mostly staying off 60-80
  km/h roads. Then that costing is planned too, with the same verified-only and unpaved loops, and replaces the
  default only if its own time still beats it by more than the slack.
- `shortest` ignores `use_ferry`, so it sits out when ferries are avoided.
- With a flat 60 s slack, the same 53 trips came out at median +0 s, max +61 s against the best time any costing or
  the previous graph found. Groningen to Maastricht: 498 instead of 515 min.
- Cost: four extra `route` calls per fastest request, in parallel with the default; a second plan only when it pays.

### Quiet profile

`use_primary: 0` alone barely moves a route: it adds a cost factor of 0.6 to primary and 0.3 to secondary roads, while a
50 km/h main road is still ridden at the 45 km/h cap against 30 km/h on a residential street. Measured on four
Amersfoort crossings, it changed none of them.

- The quiet profile asks `motor_scooter` for `use_primary: 0` and `top_speed: 30` (`QUIET_TOP_SPEED_KMH`), so a main
  road no longer outruns a 30 km/h street. At 35, Leusden to Hoogland stayed on the main roads (65%).
- The capped search gives wrong times. Each leg of the chosen route is re-traced with `trace_route` (`edge_walk`,
  default costing, same format and instructions), so geometry stays and times, instructions and `duration` are
  real. Legs are joined again for a trip with stops; a zero-length leg keeps its own. The re-traced route is classified.
- If re-tracing fails, the fastest route is returned with `"profile": "fastest"`.
- `main_road_m` is the classified length on motorway, trunk, primary and secondary roads, for every route.
- Measured on 2026-11-17 (graph with verified moped paths at road class residential), share of main road for the
  fastest and the quiet route: Bergkwartier → Soesterkwartier 72% → 14% for +1.0 min; Schothorst → Kruiskamp
  46% → 0% for +0.1 min; Nieuwland → Liendert 50% → 0% for +4.1 min; Leusden → Hoogland 65% → 6% for +4.8 min.

### Alternatives

Valhalla only returns alternates from its bidirectional search: a time-dependent request (`date_time` type 0, 1 or 2)
silently returns none. The bidirectional search gives worse moped routes (`routing/README.md`, "Search
configuration"), so:
1. The primary route comes from the usual time-dependent request, so it's the same route as without `alternatives`.
2. A second request uses `date_time` type 3 (a fixed time, so time-conditional access is still evaluated) at the
   requested time or now, with `alternates: 2`. Valhalla's `max_alternates` is 2.
3. A third request plans the other profile: quiet when the primary is fastest, fastest when it's quiet. That route is
   the first candidate, then Valhalla's alternates (fastest profile).
4. Candidates that share 90% or more of their edge length (by OSM way) with the primary or an already kept route are
   dropped. The rest are kept in that order, up to `alternatives`.
5. Each kept route is classified on its own and gets its own `route_id` and `profile`. With `verified_only`, both requests run the
   verified-only loop; the second loop excludes the unverified edges of all its routes together.

The response keeps Valhalla's own layout for several routes:
- OSRM: `routes` holds the primary first, then the alternatives. `waypoints` are the primary's.
- Native: `trip` is the primary; `alternates: [{"trip": …}, …]` holds the alternatives.
- `naviscoot` describes the primary as before, plus `naviscoot.alternates`: one entry per alternative in the same
  order as `routes[1…]` or `alternates[…]`, each with the full classification, `route_id`, `verified_only` and so on.
  It's present (possibly empty) whenever `alternatives` is above 0.
- If the second request fails but Valhalla is up, the primary is returned with `alternates: []`.

Measured: Domplein → Amersfoort with `alternatives: 2` returns 22.19 km (the N237 route, as without alternatives),
25.35 km and 25.92 km.

### Avoid unpaved

Valhalla 3.9.1 parses `exclude_unpaved` for every costing, but only the `auto` costing checks it.
`motor_scooter`'s `Allowed()` ignores it, and no local case changed with it on. So the service does it with the
verified-only mechanism:
1. The edge walk also reads `edge.unpaved`.
2. Unpaved edges inside a leg get an `exclude_locations` point at their midpoint. The leading and trailing unpaved run
   of each leg is left alone, as Valhalla's own option does, because the rider has to start or end there.
3. Verified-only points always go first. Unpaved points are only added once a route has no avoidable unverified edge
   left. If a later round brings an unverified path back, the last verified-clean route is returned. Avoiding unpaved
   never costs a verified-only result.
4. Rounds count toward `MAX_VERIFIED_REQUESTS`. A failed round or the cap ends the loop, and the last good route is
   returned.

`naviscoot.avoid_unpaved` is `{"converged": true|false, "remaining_m": n}` on every route when `avoid.unpaved` is
on. `remaining_m` is the unpaved length still inside the route, excluding the leading and trailing runs.

Local cases used by the integration tests:

| Option | Trip | Default | With the option |
|---|---|---|---|
| `ferries` | Amsterdam Centraal → Buiksloterweg | 1.26 km over the IJ ferry | 12.82 km, no ferry |
| `unpaved` | 52.10483, 5.60555 → 52.07886, 5.66514 | 6.89 km, 0.52 km unpaved mid-route | 7.38 km, none |
| `main_roads` | Arnhem 51.97709, 5.89902 → 51.95638, 5.90813 | 3.58 km, 1.47 km primary/trunk | 3.75 km, none |

### `POST /reports`, `GET /reports`

```json
{"lat": 52.1561, "lon": 5.3878, "time": "2026-11-14T18:05:00+01:00", "note": "G11 sign here", "route_id": "uuid"}
```

- `lat` and `lon` are required. `time` (ISO 8601) defaults to the moment of receipt and is stored in UTC. `note` (≤ 2,000
  characters) and `route_id` are optional. The response is `201` with the stored report, including `id` and `received_at`.
- `GET /reports` returns `{"reports": [...]}` in the order received.
- **Store: append-only JSON Lines** at `REPORTS_PATH`. Each report is one line, written with `fsync` before the response.
  The file is read into memory at start.
  - Why not SQLite: a personal app produces a handful of reports a week. JSONL needs no native module and no schema
    migration, and it is readable with `cat`. `node:sqlite` still prints an ExperimentalWarning on Node 24.14.
  - A partial last line left by a crash mid-write is dropped at start; any other unreadable line stops the server.
