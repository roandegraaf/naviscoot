# Next slice — moped-nav

Read `docs/slides/moped-nav/OVERVIEW.md` first: it's the north star and guardrail. Then read the `## Current state` header of
`docs/slides/moped-nav/PROGRESS.md` and the slice 4 and 5 entries. Read `api/README.md` (endpoints, `format: osrm`, the
`naviscoot` key) and look at `docs/mockup.html` (layout reference). Follow `~/.claude/skills/native-app-testing/SKILL.md` for
every simulator run: headless `simctl` + `idb`, never take over the user's cursor, keyboard or window focus.

## This slice
Start the iOS app: an Xcode project with destination search and the route preview, talking to the **local** API. Targets
these OVERVIEW items:
- "Search finds addresses and places": GIVEN the app, WHEN typing a street address or a place such as a station, THEN both
  appear and selecting one opens the route preview.
- "Preview shows what the route consists of": GIVEN a selected destination, WHEN the preview opens, THEN it shows time,
  distance, the distance per type and unverified stretches drawn differently on the map.

Guidance (Ferrostar navigation, voice, rerouting, warnings, report button) is the next slice. Pick the libraries now so the
next slice can build on them.

## Scope boundaries
- Do:
  - **Project:** `ios/` with a native SwiftUI app (iOS 18+ is fine), built with `xcodebuild` from the command line.
    - Use Swift Package Manager for MapLibre Native and Ferrostar. Pin exact versions and check their current docs via `ctx7` first; this repo has no SPM history yet.
    - Map tiles from OpenFreeMap.
  - **API client:** `POST /route` with `x-api-key` and `format: osrm`.
    - The base URL and key come from build settings or an xcconfig that is not committed (provide a committed `*.example`).
    - In the simulator the local API on `127.0.0.1:8080` is reachable. It reads `routing/build/nl/fused_access.csv` and needs Valhalla on 8002 (`routing/serve.sh start`).
    - Parse the OSRM body with Ferrostar's parser if practical, and read the top-level `naviscoot` key separately (stretches, `totals_m`).
  - **Search:** PDOK Locatieserver (`suggest` then `lookup`, no key) for addresses; `MKLocalSearch` for places such as stations.
    - Show one merged list.
    - Selecting a result → route preview from the current location to it.
    - The simulator location is set with `simctl location`, e.g. Amersfoort centre.
  - **Preview:**
    - Time and distance.
    - Distance per class: carriageway / moped path / unverified, from `totals_m`.
    - The route line drawn per stretch, with unverified stretches clearly different (colour + dash).
    - A "verified roads only" toggle that re-requests with `verified_only: true`.
    - Large type and touch targets per the mockup.
  - **Tests:** unit tests for the API client/parsing (stretch-to-polyline split, totals) and for the search merge.
  - **UI proof:** a simulator run that types an address and a station, selects one and screenshots the preview. Use the `verified-only-north-south` case's endpoints so an unverified stretch is visible.
- Don't:
  - No Coolify deployment, hostname or DNS. The OVERVIEW item "The API is live and protected" needs the user's hostname choice and go-ahead. Leave it for a later slice and ask the user then.
  - No guidance, voice, rerouting or report button yet.
  - Don't change the API's behaviour. Adding a field the app needs is fine if it's small and tested; re-run `cd api && npm test`.
  - Interface language: English labels (current assumption in the OVERVIEW's open questions). Keep the strings in one place so a Dutch switch stays cheap.

## Done when
Tick each box in this file as it's met; a resumed attempt picks up at the first open one.
- [ ] [user-gated] The user has reviewed the five forbidden → allowed flips of the newer-NDW rule and the Valeriusplein override
      (`docs/audit/conflicts.md`). Also: the unverified penalty (15 km/h) and built-up proxy are placeholders to sanity-check.
- [ ] `ios/` builds with `xcodebuild` for the simulator. Package versions are pinned, and the local API URL and key are not committed.
- [ ] GIVEN the app in the simulator, WHEN typing a street address and then a station name, THEN both kinds of result appear
      (exercised in the simulator, screenshots saved to the scratchpad).
- [ ] GIVEN a selected destination, WHEN the preview opens, THEN time, distance and the per-class distances are shown, and they
      match the API's `totals_m` for that route.
- [ ] Unverified stretches are drawn differently on the map, and the verified-only toggle removes them (exercised with the
      `verified-only-north-south` endpoints).
- [ ] Unit tests for the client and the search merge pass via `xcodebuild test`. `cd api && npm test` and `cd data && uv run pytest` still pass.

When finished, run `/handoff` to record progress and write the next slice.
