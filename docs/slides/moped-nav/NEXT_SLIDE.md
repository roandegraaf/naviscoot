# Next slice — moped-nav

Read `docs/slides/moped-nav/OVERVIEW.md` first: it's the north star and guardrail. Then read the `## Current state` header of
`docs/slides/moped-nav/PROGRESS.md` and the slice 7 entry. Read `routing/README.md` ("Refresh"), `api/README.md` and
`ios/README.md` (Setup, `Local.xcconfig`).

## This slice
Deploy the routing service on `coolify-personal`. Targets the last automatable OVERVIEW item:
- "The API is live and protected": GIVEN the deployed service, WHEN called without the API key, THEN it is refused, and
  with the key it returns a route.

**Hostname and go-ahead are given** (see the boxes). **Still blocked on access, see the third box.** Original preconditions:
1. The hostname for the API (for example a subdomain of a domain they own, pointed at `coolify-personal`).
2. An explicit go-ahead to deploy: containers, volumes, DNS/proxy config and an uploaded graph of about 1.3 GB.

## Scope boundaries
- Do:
  - Two services on `coolify-personal`:
    - Valhalla 3.9.1 (`valhalla_service` on the uploaded `routing/build/nl/` unit, internal only, never public).
    - The API (`api/`, Node, `API_KEY` from a Coolify secret, `VALHALLA_URL` pointing at the internal Valhalla).
    - TLS via Coolify's proxy on the chosen hostname.
  - The graph is built locally (OVERVIEW) and uploaded; the server only serves.
    - A script (for example `routing/deploy.sh`) uploads `tiles.tar`, `valhalla.json` (paths rewritten for the server),
      `admins.sqlite` and `fused_access.csv`, then restarts both services.
    - Measure the server's free RAM and disk first; the OVERVIEW's 2 GB is an unmeasured estimate. Valhalla served 1.7 GB
      locally.
  - `api/data/` (reports) on a persistent volume.
  - Prove: `curl` without the key → 401, with the key → a route for `verified-only-north-south`; `GET /health` open;
    Valhalla's port not reachable from outside.
  - Point the app at the hostname via `ios/Config/Local.xcconfig` (https, so no local-networking exception needed) and run
    the UI proof against it once (reports from the proof will land on the server; note it).
- Don't:
  - Expose Valhalla publicly, commit the API key, or change API behaviour.
  - No CarPlay, offline routing, favourites or recent places.

## Done when
Tick each box in this file as it's met; a resumed attempt picks up at the first open one.
- [x] [user-gated] The user gave the hostname and the deploy go-ahead (`naviscoot.appj.nl`, server `localhost` on `coolify-personal`, repo on their GitHub).
- [x] Compose stack, API image and graph upload script exist and pass the 401/route/report checks locally; private repo https://github.com/roandegraaf/naviscoot pushed.
- [ ] [user-gated] Access for the deploy: either the Coolify API (the `coolify-personal` MCP loaded in the worker session, or the Keychain token read allowed) or the user does steps 2-4 of `routing/README.md` "Deploy (Coolify)" by hand; plus SSH (`DEPLOY_HOST=<user>@<server>`) for `routing/deploy-graph.sh`.
- [ ] [user-gated] The user has reviewed the five forbidden → allowed flips of the newer-NDW rule and the Valeriusplein override
      (`docs/audit/conflicts.md`), and the placeholder choices of slices 1-7 (penalty 15 km/h, built-up proxy, 1,000 m
      warning lead, Dutch warning wording, deviation 40 m, colours, icons, copy).
- [ ] GIVEN the deployed service, WHEN called without the API key, THEN 401; with the key, THEN a route (exercised with curl).
- [ ] Valhalla is not reachable from outside the server (exercised).
- [ ] The iOS UI proof passes against the deployed API.
- [ ] `cd api && npm test` and `cd data && uv run pytest` still pass.

Still `[user-gated]` in the OVERVIEW after this: "Guidance continues with the screen locked" and "A real ride is legal end
to end" (real iPhone rides; background audio and location are configured but unproven).

When finished, run `/handoff` to record progress and write the next slice.
