# Next slice — moped-nav

Read `docs/slides/moped-nav/OVERVIEW.md` first: it's the north star and guardrail. Then read the `## Current state` header of
`docs/slides/moped-nav/PROGRESS.md` and the slice 6 entry. Read `ios/README.md` (pins, xcconfig, `-skipMacroValidation`,
the XCUITest UI proof) and `api/README.md` (`POST /reports`, `GET /reports`). Look at screen 3 of `docs/mockup.html` (riding).
Follow `~/.claude/skills/native-app-testing/SKILL.md`. Drive the simulator through XCUITest: idb taps don't work on Xcode 27.

## This slice
Turn-by-turn guidance in the iOS app, against the **local** API. Targets these OVERVIEW items:
- "Turn-by-turn guidance with Dutch voice": GIVEN a simulated ride in the iOS simulator, WHEN approaching a turn, THEN the
  banner shows distance and street and a Dutch instruction is spoken.
- "Reroutes when off route": GIVEN a simulated ride that leaves the route, WHEN the deviation is detected, THEN a new route is
  requested and guidance continues.
- "Warns before an unverified stretch": GIVEN a route with an unverified stretch, WHEN approaching it, THEN a warning is shown
  and spoken.
- "Report button records the location": GIVEN a ride in progress, WHEN the report button is tapped, THEN the position and time
  are stored on the server and retrievable as a list. Here "the server" means the local API; the deployed one comes later.

## Scope boundaries
- Do:
  - **Ferrostar session:** wire the preview's Start button to a Ferrostar navigation session (FerrostarCore 0.59.0 is already
    pinned; add the `FerrostarMapLibreUI`/`FerrostarSwiftUI` products if useful).
    - Routes come from `NaviscootClient` through `RouteProvider.customProvider` (`CustomRouteProvider.getRoutes(userLocation:waypoints:)`),
      so rerouting goes through the API too. Keep the `naviscoot` metadata of the active route (stretches, totals) next to Ferrostar's state.
    - Rerouting re-requests with the same `verified_only` choice. Check Ferrostar's deviation detection and its reroute
      callback in the 0.59.0 sources (re-clone the tag or use ctx7).
  - **Banner and voice:** large banner per the mockup, with distance to the maneuver and the street.
    - Spoken instructions in Dutch via the system synthesizer (`nl-NL`); the API already returns Dutch `voiceInstructions` (`language: nl-NL`).
    - English UI labels stay in `Strings.swift`.
  - **Unverified warning:** before an unverified stretch, show a warning chip ("Unverified path in 1.2 km, for 300 m") and speak a
    Dutch warning once per stretch.
    - Use the stretch shape indices against the route geometry and the user's progress along it.
    - Pick and record a lead distance (placeholder).
  - **Report button:** `POST /reports` with position, time and `route_id`; visible confirmation; queue and retry if the request
    fails. `GET /reports` shows it.
  - **Ride screen:** current speed, the speed limit of the current stretch (45 carriageway; 30/40 moped path per the
    OVERVIEW — the API's stretches don't carry built-up yet, so decide: add a small field to the API or derive it),
    remaining time and distance, End button, screen kept awake (`isIdleTimerDisabled`).
    - Background audio and location are configured, but proving them with a locked screen is the user's real-device item.
  - **Simulated ride:** in the simulator, use Ferrostar's simulated location provider (or `simctl location` with a GPX-like
    route) along the `verified-only-north-south` default route to Woudenbergseweg 42 Maarsbergen, which crosses the 483 m
    unverified stretch.
    - The proof must show: a banner with distance and street; a spoken Dutch instruction (assert via a hook that
      records what was handed to the synthesizer, since audio can't be heard in CI); a reroute after a forced deviation;
      the unverified warning; a report retrievable from `GET /reports`.
    - Screenshots go to the scratchpad.
  - **Tests:** unit tests for the warning trigger (distance-to-next-unverified from progress), the report queue, and the
    custom route provider's mapping.
- Don't:
  - No Coolify deployment, hostname or DNS. "The API is live and protected" needs the user's hostname choice and go-ahead.
    If the rest of the task is done, end the slice with `needs_input` asking for both instead of deploying.
  - No CarPlay, offline routing, favourites or recent places.
  - Don't change API behaviour beyond small, tested additions the app needs; re-run `cd api && npm test`.

## Done when
Tick each box in this file as it's met; a resumed attempt picks up at the first open one.
- [ ] [user-gated] The user has reviewed the five forbidden → allowed flips of the newer-NDW rule and the Valeriusplein override
      (`docs/audit/conflicts.md`). Also: the unverified penalty (15 km/h), the built-up proxy and slice 6's placeholder UI
      choices (colours, icons, copy) are placeholders to sanity-check.
- [ ] Start opens guidance; GIVEN a simulated ride, WHEN approaching a turn, THEN the banner shows distance and street and a
      Dutch instruction is handed to the synthesizer (exercised in the simulator, screenshot saved).
- [ ] GIVEN the simulated ride leaves the route, WHEN the deviation is detected, THEN a new route is requested from the API and
      guidance continues (exercised).
- [ ] GIVEN the route with the 483 m unverified stretch, WHEN approaching it, THEN the warning is shown and spoken (exercised).
- [ ] GIVEN a ride in progress, WHEN the report button is tapped, THEN the report appears in `GET /reports` of the local API with
      position, time and `route_id` (exercised).
- [ ] Unit tests pass via `xcodebuild test` (scheme `Naviscoot`); the UI proof passes (scheme `NaviscootUITests`);
      `cd api && npm test` and `cd data && uv run pytest` still pass.

When finished, run `/handoff` to record progress and write the next slice.
