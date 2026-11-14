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
  "language": "nl-NL"
}
```

- `format`: `valhalla` (native JSON, `trip.legs[0].shape`) or `osrm` (Valhalla's extended OSRM format with banner and
  voice instructions, `routes[0].geometry`). Ferrostar's Valhalla integration only parses the OSRM format, so the iOS app
  will use `osrm`.
- The server always sends `costing: motor_scooter` and `date_time: {"type": 0}` (see `routing/README.md`, "Search
  configuration"). Only origin and destination are supported, so there is always one leg.
- The response is Valhalla's own response, unchanged, plus one extra top-level key `naviscoot`:

```json
{
  "trip": {"...": "native Valhalla, or routes/waypoints/code for format osrm"},
  "naviscoot": {
    "route_id": "uuid",
    "format": "valhalla",
    "length_m": 36254,
    "edge_length_m": 36246,
    "totals_m": {"carriageway": 20961, "moped_path": 14810, "unverified": 483, "forbidden": 0},
    "stretches": [
      {"class": "unverified", "start_shape_index": 1341, "end_shape_index": 1377, "first_edge": 412, "last_edge": 413,
       "length_m": 483, "way_ids": [1497802338]}
    ],
    "warnings": [],
  }
}
```

The example is the default route of `verified-only-north-south`. With `verified_only: true` the same trip comes back as
39.54 km with no unverified stretch and `"verified_only": {"requests": 2, "excluded_points": 2, "converged": true}`.

Errors:
- `400`: invalid body.
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
   (`trip.legs[0].shape` or `routes[0].geometry`, both polyline6).
4. **Lengths add up exactly.** Valhalla's edge lengths are rounded to whole metres and sum to slightly less than the
   route length (measured: 8 m short on 36 km, 27 m on 129 km, at most 0.03%). Stretch lengths are the edge lengths
   scaled to the route length and rounded with the largest-remainder method, so `totals_m` and the stretches sum to
   `length_m` (the route length rounded to whole metres) with zero tolerance. The raw sum stays visible as
   `edge_length_m`; a gap over 0.5% adds a warning.

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
