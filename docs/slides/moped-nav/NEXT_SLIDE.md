# Next slice — moped-nav

Read `docs/slides/moped-nav/OVERVIEW.md` first: it's the north star and guardrail. Then read the
`## Current state` header of `docs/slides/moped-nav/PROGRESS.md` and the slice 2 entry. `data/README.md`
describes `data/build/fused_access.csv`, the input of this slice.

## This slice
Turn the fused access into a routable graph and prove it with regression routes:
- rewrite tags into an OSM extract;
- build a patched Valhalla graph locally in Docker;
- add a regression suite that every rebuild must pass.

This targets these OVERVIEW items:
- "An override wins over every source"
- "Never routes over a forbidden way"
- "Uses moped paths instead of detouring"
- "Stays off the carriageway where the moped path is mandatory"
- "Snorfiets tags grant nothing"
- "Routing outside the region still works"

## Scope boundaries
- Do:
  - **Tag rewriting** (Python, in `data/`, e.g. `uv run rewrite`)
    - Read `data/raw/netherlands-latest.osm.pbf` and `data/build/fused_access.csv`; write a routable NL extract to
      `data/build/` (gitignored).
    - For each cycle path in the CSV, set an explicit moped tag from the fused status:
      - allowed → `moped=designated`;
      - forbidden → `moped=no`;
      - unknown → a marker the patched Lua turns into "allowed with a penalty" (the unverified class).
    - Outside the region, leave OSM as is.
    - Record the class so a later API slice can classify route stretches. Valhalla does not return custom tags;
      the likely route is `trace_attributes` edge `way_id` looked up in the CSV. Confirm this is feasible, don't build the API.
  - **Valhalla** (in `routing/`)
    - First, confirm that the pinned Valhalla version still applies its OSM tag transform through `lua/graph.lua`
      (check the source tree or changelog of that tag). If it doesn't, apply the three fixes in the tag-rewriting step
      instead and note it in `routing/README.md`.
    - Pin a Valhalla Docker image version and patch its `graph.lua` for the three stock defects from the OVERVIEW:
      `moped=use_sidepath` is ignored, `mofa` leaks into moped access, and moped paths get 8 km/h.
    - Apply the speed rules: 45 on the carriageway, 30 on a moped path in the built-up area, 40 outside.
    - Give unverified cycle paths a reduced edge speed as their penalty. Pick a first value and record it as a
      placeholder to tune.
    - Build tiles for all of the Netherlands locally with Docker and serve them locally. No deploy to Coolify.
  - **Verified-only alternative**: validate the proposed mechanism (re-request with `exclude_locations` on unverified
    stretches until none remain) on at least one real route. Report whether it converges and how many re-requests
    it needs. If it doesn't converge, propose an alternative such as a second costing or a separate graph.
  - **Regression suite** (a script or pytest marked as needing the local Valhalla)
    - Real cases taken from the data:
      - a G11 path, a G13 path, a footway, an autoweg and an autosnelweg that a naive route would use;
      - Utrecht Domplein → Amersfoort centre, under 25 km along the N237 (stock gives 42.6 km);
      - a `moped=use_sidepath` road with a parallel G12a path;
      - a cycle path with `mofa=yes` and no moped information;
      - the override way 573252346;
      - a destination about 100 km from Amersfoort.
    - Each case states the way ids it must avoid or use.
    - The suite fails loudly with a non-zero exit.
- Don't:
  - No API service, no Coolify deployment, no iOS.
  - No one-command refresh yet; that is a later slice. Separate commands are fine.
  - Don't change the fusion rules from slice 2, except to fix a bug found along the way.
    If you do fix one, re-run `uv run pytest` and `uv run audit`.
  - No WKD.

## Done when
Tick each box in this file as it's met; a resumed attempt picks up at the first open one.
- [ ] [user-gated] The user has made the first commit (command in `docs/slides/moped-nav/status/slice-1.md`) and decided
      whether the generated `docs/audit/*` is committed or gitignored. The user should also review the five forbidden → allowed
      flips of the newer-NDW rule and the Valeriusplein override (`docs/audit/conflicts.md`).
- [ ] The tag-rewriting command produces a routable NL extract in which every cycle path in `fused_access.csv` carries
      the fused class. A unit test covers allowed, forbidden and unknown, and that `mofa=*` grants nothing.
- [ ] The patched `graph.lua` is in `routing/` and fixes the three stock defects. A small synthetic OSM file proves each fix
      (e.g. a graph built from a hand-written .osm, or a Lua unit test).
- [ ] A local Valhalla built from the rewritten extract answers `motor_scooter` routes. Build command, image version,
      build time and tile size are recorded in `routing/README.md`.
- [ ] The regression suite passes against the local Valhalla, with every case listed above.
      GIVEN Utrecht Domplein → Amersfoort centre, WHEN routed, THEN the route is under 25 km.
- [ ] The override way 573252346 is avoided: GIVEN the override, WHEN the graph is rebuilt and a route across it is
      requested, THEN the route does not use it.
- [ ] The `exclude_locations` verified-only mechanism is validated on a real route with an unverified stretch,
      and the result is recorded (converges or not, number of requests).

When finished, run `/handoff` to record progress and write the next slice.
