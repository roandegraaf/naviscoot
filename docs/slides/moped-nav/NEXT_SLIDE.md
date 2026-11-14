# Next slice — moped-nav

Read `docs/slides/moped-nav/OVERVIEW.md` first: it's the north star and guardrail. Then read the
`## Current state` header of `docs/slides/moped-nav/PROGRESS.md` and the slice 3 entry. Read
`routing/README.md`, especially "Search configuration (required)", "Route classification for the API" and "Verified-only
alternative". `data/naviscoot_data/valhalla.py` is a working Python reference for everything this slice ports to TypeScript.

## This slice
Build the thin API in `api/` (TypeScript, Node) in front of the local Valhalla:
- route with per-stretch classification;
- the verified-only alternative;
- a reports endpoint;
- a static API key.

Everything runs and is tested locally. No deployment.

This targets these OVERVIEW items:
- "Unverified stretches are reported per route"
- "A verified-only alternative is available"
- the local half of "The API is live and protected" (refused without the key, a route with it). Going live on Coolify is a later,
  user-approved slice.

## Scope boundaries
- Do:
  - **Project:** `api/` with a lockfile, `tsc` typecheck and a test runner. Pick a small HTTP framework (e.g. Fastify or Hono) and
    note why in `api/README.md`. Config by env vars: `VALHALLA_URL` (default `http://127.0.0.1:8002`), `API_KEY`, the
    fused CSV path, the reports store path, and the port.
  - **Auth:** every endpoint except a health check requires the API key header (e.g. `x-api-key`). Wrong or missing → 401.
  - **Route endpoint** (e.g. `POST /route` with origin, destination and `verified_only`):
    - calls Valhalla `motor_scooter` **with `date_time: {"type": 0}`** (required, see routing README);
    - returns the Valhalla trip for the client (shape, maneuvers; Ferrostar's Valhalla adapter will consume it later, so keep
      the native Valhalla response available rather than reinventing it);
    - plus a classification: per stretch carriageway / moped path / unverified, with totals per type.
  - **Classification rules:**
    - Get way ids with `trace_attributes` edge_walk (`edge.way_id`, plus `edge.road_class`/`edge.use` or similar as needed).
    - Look them up in `data/build/fused_access.csv`, loaded into memory at start.
    - unknown → unverified; allowed → moped path; any other edge whose use is a cycleway/path → moped path; else carriageway.
    - Merge consecutive edges of the same class into stretches with start/end shape indices and length.
    - Totals must add up to the route length (allow rounding tolerance and state it).
  - **Verified-only:**
    - Port the `exclude_locations` loop: midpoints of unverified edges, first and last edge exempt, cap about 5 requests.
    - On a failed re-request, return the last successful route with its remaining unverified stretches flagged as
      unavoidable. Never return an error when a route exists.
  - **Reports:**
    - `POST /reports` stores position (lat, lon), time, optional note and optional route id.
    - `GET /reports` lists them.
    - Use a simple durable store (SQLite or an append-only JSON file under a gitignored data dir); say which and why.
  - **Tests:**
    - Unit tests with a mocked Valhalla for classification, totals, the verified-only loop and auth.
    - Integration tests (skippable without a local Valhalla) using real cases from `routing/regression_cases.json`: the
      `verified-only-north-south` route crosses a 483 m unverified path. GIVEN that route, the API classifies it unverified and
      the totals add up; WHEN verified-only is requested, there is no unverified stretch.
- Don't:
  - No Coolify deployment, Dockerfile push, DNS or hostname choices.
  - No iOS. No one-command refresh yet.
  - Don't change the graph, Lua or fusion unless a bug is found. If you do, rebuild and re-run all three test tiers
    (`uv run pytest`, `-m docker`, `-m valhalla`).

## Done when
Tick each box in this file as it's met; a resumed attempt picks up at the first open one.
- [ ] [user-gated] The user has reviewed the five forbidden → allowed flips of the newer-NDW rule and the Valeriusplein override
      (`docs/audit/conflicts.md`). Also: the unverified penalty (15 km/h) and built-up proxy are placeholders to sanity-check.
- [ ] `api/` builds, typechecks and its unit tests pass. `api/README.md` documents run, env vars and endpoints.
- [ ] Requests without the API key are refused (401) and with the key a route is returned (test + a live local call).
- [ ] GIVEN a route crossing an unknown cycle path, WHEN the API responds, THEN that stretch is classified unverified and the
      totals per type add up to the route length (integration test against local Valhalla).
- [ ] GIVEN that same route, WHEN verified-only is requested, THEN the result contains no unverified stretch (integration test).
- [ ] A report posted with position and time is returned by the list endpoint and survives an API restart.
- [ ] The Python regression suite still passes (`cd data && uv run pytest -m valhalla`) against the served graph.

When finished, run `/handoff` to record progress and write the next slice.
