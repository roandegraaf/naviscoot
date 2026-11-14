# Naviscoot

Turn-by-turn navigation for a Dutch bromfiets (45 km/h) that only routes where a bromfiets may legally ride.

- `data/` Python pipeline: source downloads, coverage audit, access fusion
- `routing/` Valhalla configuration and graph build
- `api/` TypeScript service in front of the routing engine
- `ios/` SwiftUI app
- `docs/` design notes, audit reports, slice plans

Start with `data/README.md`.
