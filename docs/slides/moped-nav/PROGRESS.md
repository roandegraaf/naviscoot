# Progress — moped-nav

## Current state
**Slices done:** 1 (repo + coverage audit), 2 (fusion). No commit yet; the user owns version control (command in `status/slice-1.md`).

**Invariants in force**
- Region = 50 km around 52.156, 5.387 (`geo.py`). Cycle path = OSM `highway=cycleway` way with ≥1 node in the region. Status is per whole way.
- `mofa=*`, `motor_vehicle=no`, `access=no` are never moped evidence. The moped tag wins over a contradicting `traffic_sign` on the same way.
- Precedence (user decision 2026-11-14, relayed by the orchestrator): `data/overrides.csv` > NDW sign newer than the OSM edit AND attached unambiguously > explicit OSM tag > NDW direct > NDW propagated > unknown.
  - Unambiguous: matched (not junction arm or hand-over), ≤10 m from the path, no other fitting cycle path and no cycle junction within 20 m, no OB505/OB502 sub-sign. These conditions are the orchestrator's reading of "if trustworthy", not the user's words.
  - Propagated NDW never beats OSM. Every disagreement is in `docs/audit/conflicts.md` with the reason NDW did or didn't win.
- NDW sign date = newest of `validatedOn`, `placedOn`, `registeredOn`. `lastModifiedOn` is NOT used: it tracks NDW's NWB re-link batches (2,886 regional records on 2025-09-09, NWB version 2025-09-01).
  - Of 50,959 regional G11/G12a/G13 records: 1,034 have `validatedOn`, 1,076 `placedOn`, all have `registeredOn`, 0 undated.
  - Undated records would never win on recency.
- NDW `bearing` = travel direction of the addressed traffic (calibrated: 10,375 into the path vs 367 out of it).
- `onleesbaar` sub-sign drops a sign as evidence; "snorfietsen niet / niet brommen / naar de rijbaan" only marks G11/G13 as confirmed; speed-pedelec exemptions are ignored; OB505/OB502 are not interpreted (meaning unverified).
- Downloaded data in `data/raw/`, generated data in `data/build/` (gitignored). Pending user decision on committing generated `docs/audit/*` (map.html is now 7.6 MB, conflicts.md 0.18 MB).
- No code comments unless the reason is non-obvious.

**Commands** (from `data/`, see `data/README.md`)
- `uv run fetch`: Geofabrik NL + clip to `build/region.osm.pbf`, NDW G11/G12a/G12b/G13 (20 h TTL).
- `uv run audit` (~45 s): fusion → `build/fused_access.csv` (way_id,status,source,source_id,date; one row per cycle path); `docs/audit/coverage.md`, `conflicts.md`, `map.html`; `build/handcheck_sample.json`.
- `uv run pytest`: 42 unit tests, synthetic data only.

**Key files**
- `fuse.py`: `attach` (sign → way + travel direction; junction arms; hand-over), `propagate`, `fuse_way` (precedence), `conflict_for`, `load_overrides`, `run`.
- `model.py` dataclasses; `audit.py` OSM pass (cycleways with node ids, road-node `IdSet`), slice 1 point matching, calls `fuse.run`; `report.py` reports + map; `classify.py` OSM-only rules.
- `data/overrides.csv` (1 entry, way 573252346 forbidden, not surveyed); `docs/audit/handcheck.md` hand-maintained, embedded in coverage.md.

**Numbers (OSM 2026-11-13, NDW 2026-11-14)**
- 72,552 cycle paths, 9,623 km. Unknown: OSM alone 2,117.3 km → slice 1 point evidence 1,177.9 km → fusion 1,108.4 km.
- Fused: allowed 3,297 km, forbidden 5,217 km. Propagation resolves 1,877 ways / 106 km; 6,218 signs are ambiguous at cycle junctions.
- 702 conflict rows; 66 with NDW newer.
  - 16 won by NDW (3.6 km): 11 allowed → forbidden, 5 forbidden → allowed.
  - 685 won by OSM, 1 by the override.

## Slice: 1 — repo setup and coverage audit (2026-11-14)
**Shipped**
- Repo layout (`data/ routing/ api/ ios/ docs/` with `.gitkeep`), `.gitignore`, root and data READMEs.
- uv project `naviscoot-data` with the `fetch` and `audit` entry points.
- Coverage audit report and inspection map; hand check of 10 samples.

**Key decisions**
- NDW: per-code API calls rather than the bulk file, because only the API has `lastModifiedOn`.
- Clipping: pure pyosmium rather than osmium-tool. The node pass takes 3 min and the whole clip under 5 min, so no extra system dependency.
- G12b is matched and counted but not used as evidence: a single end sign doesn't say which side is the moped path.
- Each conflict gets a likely cause:
  - "own traffic_sign agrees with NDW": OSM contradicts itself.
  - "neighbour has sign's status": a junction matching artefact.
  - "unexplained".
- Basemap: PDOK BRT grijs, because CARTO now requires an API key and OSM tiles need a referer that `file://` doesn't send.

**Notes / leftovers for fusion**
- NDW resolves 939 km of unknown with point evidence alone. 16,441 unknown ways carry no hint tags at all.
- 85% of NDW bearings are quantised to N/E/S/W, so the bearing test is weak at junctions; the 15% with precise bearings are much more trustworthy.
- Hand check: 10/10 classifications reproduce the raw data.
  - Of the 3 conflicts: 1 junction artefact, 1 genuine disagreement, 1 probably outdated OSM.
  - The "neighbour" label wrongly explains away case 10 (precise NDW bearing, newer than OSM).
- 95 OSM ways contradict themselves (moped tag vs traffic_sign).
- 1,484 signs had no cycle path within 20 m. Only 127 of them are next to a road with `cycleway*=track|lane`; most are near footways and residential roads.
- NDW `conditions.exemptions` never deviate from the sign code (0 cases), so they add nothing. Supplementary signs are common: 3,569 matched signs, e.g. "snorfietsen niet toegestaan", "onleesbaar", OB505, OB502. They are counted, not interpreted.
- The unknown hint tags (`motor_vehicle=no`, `access=no`, `mofa`) were deliberately not used in classification.

**Placeholder choices:** the trust thresholds of the newer-NDW rule (10 m, 20 m, matched only, OB505/OB502 excluded); the Valeriusplein override (now weaker evidence, see above); map colours (conflict magenta, unknown orange, NDW-allowed green dashed, NDW-forbidden blue dashed); sample seed 20261114 and strata 4 allowed / 3 forbidden / 3 conflict; NDW TTL 20 h.

**Runtime-unverified:** none. The map was opened from `file://` in Chrome via DevTools: 27,668 lines and the PDOK tiles load, way and sign popups work, no console errors.

**Open (user):** the first commit. Command in `docs/slides/moped-nav/status/slice-1.md`.


## Slice: 2 — fusion of OSM and NDW (2026-11-14)
**Shipped**
- `data/naviscoot_data/fuse.py`, `model.py`; `audit.py` and `report.py` extended. pytest dev dependency, `data/tests/test_fuse.py` (42 tests).
- `data/overrides.csv` with one real entry; `data/build/fused_access.csv`.
- `coverage.md`: fusion status table, unknown-by-stage table, delta vs slice 1, source breakdown, sign attachment table, OB505/OB502 note, override table, conflict summary. New `docs/audit/conflicts.md`.
- Map: layers for direct and propagated NDW statuses and for the override list; sign popups show the attached way or why a sign is ambiguous.
- Hand check of 5 random propagated ways (5/5 reproduce, direction and junctions checked independently from the pbf) appended to `handcheck.md`.

**Key decisions**
- The slice 1 point-evidence figure is still computed with the unchanged slice 1 matching, so 1,177.9 km stays reproducible.
- Attachment: precise bearings prefer a path within 20°; a cycle junction (≥3 arms) within 8 m makes the sign pick the arm leaving in its travel direction (≤20° precise / ≤45° quantised, beating the next arm by ≥15°), else ambiguous. A sign <5 m before the end of its path is handed to the next path when it is a plain joint.
- Propagation stops at road junctions (motor roads incl. `service` except driveway/parking_aisle; footway/path/track/steps don't stop) and cycle path branches, also partway along a path. On the signed path the scan starts at the sign. A next path with such a junction partway along it is not entered, because status is per whole way. It also stops at dead ends, a next path carrying its own G-sign, a path whose explicit OSM tag says the opposite (that path still gets its conflict row), a same-direction G12b, closed loops, and after 5 km.
- Override entry: hand-check case 10 (Valeriusplein), forbidden as the safe side, marked not surveyed.
  - Its NDW sign turned out to be registered in 2016; the 2025 date was the re-link batch. Under the sign-date rule OSM's 2023 edit is newer.
  - The entry is kept for the user to review, with a corrected reason.
- Newer-NDW rule: see the Current state header. Signs carrying OB505/OB502 are excluded from it.
  - Why: one forbidden → allowed flip was a G12a+OB505 in Nieuwkoop where OSM says G11, the same pattern as hand-check case 8.
- Conflicts are per way (not per sign-way pair as in slice 1); the slice 1 per-pair tables were removed from coverage.md.

**Notes / leftovers**
- Propagation adds only 106 km. Most propagated ways are short bridges, tunnels and segments between two parts of one path; 64% are one hop from the sign. Junctions anywhere along a path stop it, which is deliberate but conservative.
- Bug found by review and fixed in this slice: the first version checked junctions only at path ends. That gave 180 km of propagation, including paths entered across a road crossing partway along them.
- 2,330 ways (62.3 km) resolved by slice 1 are unknown after fusion, mostly because their sign is now ambiguous at a cycle junction.
- Hand-check case 9 (127521919) still attaches to the OSM-allowed way; OSM wins.
- Audit runtime went from 17 s to ~45 s (road-node pass and candidate tracking).
- WKD is still unused; 1,035 km of unknown cycle paths remain and become "unverified" in routing.

**Placeholder choices:** the trust thresholds of the newer-NDW rule (10 m, 20 m, matched only, OB505/OB502 excluded); the Valeriusplein override (now weaker evidence, see above); map colours for the new layers (override black, propagated allowed light green dotted, propagated forbidden light blue dotted); thresholds 8 m junction radius, 5 m hand-over, 15° arm margin, 20° precise tolerance, 5 km propagation cap.

**Runtime-unverified:** none. The map was opened from `file://` in Chrome via the DevTools MCP:
- 27,100 ways and 18,595 signs; all 9 overlays listed (propagated: 362 allowed, 1,515 forbidden).
- Re-checked after the precedence change.
- Way and sign popups work on a propagated way.
- 48/48 PDOK tiles load; no console messages.
