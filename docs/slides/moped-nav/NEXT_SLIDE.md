# Next slice — moped-nav

Read `docs/slides/moped-nav/OVERVIEW.md` first: it's the north star and guardrail. Then read the `## Current state` header of
`docs/slides/moped-nav/PROGRESS.md` and the slice 3 and 4 entries. Read `data/README.md` (fetch is incremental, `--force`
re-downloads), `routing/README.md` ("Commands", "Build figures", "Regression suite") and `api/README.md` ("Tests").

## This slice
Make the data refresh one command, run locally. It targets this OVERVIEW item:
- "Data refresh is one command": GIVEN newer OSM and NDW data, WHEN the refresh command runs, THEN it rebuilds the fused
  extract and graph and fails loudly if a regression case breaks.

The command chains the existing steps and gates the new graph on the regression suite, so a broken graph never replaces
the one being served. Uploading tiles to Coolify is not part of this slice. The output should be a finished, tested
`tiles.tar` that a later deploy slice can upload.

## Scope boundaries
- Do:
  - **One entry point**, e.g. `./refresh.sh` at the repo root or `routing/refresh.sh`. Say which and why in `routing/README.md`.
  - **Chain:** `uv run fetch` (pass `--force` through as an option) → `uv run audit` → `uv run rewrite` → `routing/build.sh all`.
    - Build into a **staging** output dir, e.g. `OUT=routing/build/nl-next`. `build.sh` and `serve.sh` already read `OUT`, `NAME` and `PORT`.
  - **Gate:**
    - Serve the staging graph on a spare port (e.g. 8003, its own container `NAME`).
    - Run `uv run pytest -m valhalla` with `VALHALLA_URL` pointing at it.
    - Run the API integration tests with `REQUIRE_VALHALLA=1` and `VALHALLA_URL` set (`cd api && npm run test:integration`).
    - Any failure → non-zero exit, a clear message naming the failed step, the staging container stopped, and the live
      graph (`routing/build/nl`, port 8002) untouched.
  - **Promote:** only on success. Swap staging into `routing/build/nl` (keep the previous build as `nl-prev` for one rollback),
    then restart `routing/serve.sh`. Note: `valhalla.json` contains in-container paths with the `OUT` dir in them, so
    regenerate it for the final location (`build.sh config` with the final `OUT`) or make the config relocatable.
  - **Report:** print a short summary at the end: OSM and NDW dates, fused counts (allowed/forbidden/unknown), tile size,
    test counts, total time. Append the same line to a gitignored log, e.g. `routing/build/refresh.log`.
  - **Prove the gate fails loudly:** add a deliberately broken case to a copy of `regression_cases.json`, or point the gate at
    a stock-Lua graph (`GRAPH_LUA=stock`). Show a non-zero exit and that the live graph was not swapped. Make the cases file
    path an env var if needed (the Python test reads `routing/regression_cases.json`). Don't commit the broken case.
  - Run the real refresh once end to end (expect ~10 minutes: rewrite ~330 s, tiles ~110 s, audit ~45 s, fetch depends on
    Geofabrik). Record the timing in `routing/README.md`.
- Don't:
  - No Coolify deployment, no upload, no DNS or hostname choices. Those need the user's go-ahead and belong to a later slice.
  - No iOS.
  - Don't change fusion rules, Lua or the API behaviour. A bug found on the way may be fixed; then re-run all test tiers
    (`uv run pytest`, `-m docker`, `-m valhalla`, `cd api && npm test`).
  - Disk: the tile build needs ~2 GB per output dir. Check free space before keeping three dirs (`nl`, `nl-next`,
    `nl-prev`); if tight, keep only `nl-prev`'s `tiles.tar` and `valhalla.json`.

## Done when
Tick each box in this file as it's met; a resumed attempt picks up at the first open one.
- [ ] [user-gated] The user has reviewed the five forbidden → allowed flips of the newer-NDW rule and the Valeriusplein override
      (`docs/audit/conflicts.md`). Also: the unverified penalty (15 km/h) and built-up proxy are placeholders to sanity-check.
- [ ] One command runs fetch → audit → rewrite → build → gate → promote, documented in `routing/README.md`.
- [ ] GIVEN a regression case that fails on the new graph, WHEN the refresh runs, THEN it exits non-zero, names the failed
      step, and the served graph on 8002 is unchanged (exercised, not just written).
- [ ] A real end-to-end refresh succeeded: the new graph is served on 8002, `uv run pytest -m valhalla` and
      `cd api && npm run test:integration` pass against it, and the timing is recorded.
- [ ] Previous build kept for one rollback, with the rollback command documented.
- [ ] `uv run pytest` and `cd api && npm test` still pass.

When finished, run `/handoff` to record progress and write the next slice.
