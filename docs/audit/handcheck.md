Checked by hand on 2026-11-14 against the data snapshot above (Geofabrik extract of 2026-11-13, NDW of
2026-11-14). The sample is drawn with seed 20261114 by `uv run audit` (4 allowed and 3 forbidden ways that
have a matched NDW sign and no conflict, plus 3 conflict ways) and written to `data/build/handcheck_sample.json`.
For each way, the tags were fetched from the OSM API at the exact version that was classified
(`/api/0.6/way/{id}/{version}`). The NDW record was read from the raw API download, and every highway within
25 m of the sign was listed to judge the match.

| # | Kind | Way | Raw OSM tags (relevant) | NDW record | Audit says | Verdict |
|---|---|---|---|---|---|---|
| 1 | allowed | 24919350 v4 | `moped=designated`, `traffic_sign=NL:G12a` | G12a, 2022-06-21, 3.4 m, nearest cycle path | allowed (OSM), NDW agrees | correct |
| 2 | allowed | 158091113 v2 | `moped=designated` | G12a, 2026-03-31, 2.2 m, at a joint with another `moped=designated` path | allowed (OSM), NDW agrees | correct |
| 3 | allowed | 1254981627 v2 | `moped=designated`, `traffic_sign=NL:G12a` (Koningsweg, Arnhem) | G12a, 2022-03-01, 2.4 m, parallel to the path | allowed (OSM), NDW agrees | correct |
| 4 | allowed | 1389808180 v1 | `moped=designated`, `traffic_sign=NL:G12a`, `mofa=designated` | G12a, 2022-09-26, 3.4 m, at a joint with another G12a path | allowed (OSM), NDW agrees | correct |
| 5 | forbidden | 41340572 v8 | `traffic_sign=NL:G11`, no moped tag | G11, 2022-06-15, 1.0 m, parallel | forbidden (traffic_sign), NDW agrees | correct |
| 6 | forbidden | 860888950 v1 | no moped or sign tags (Bokkedijk, Renkum) | G11, 2022-03-23, 2.9 m, at a three-way junction with two G12a paths that run across the sign bearing | unknown in OSM, forbidden from NDW | plausible: the bearing points along Bokkedijk, so the G11 marks where the G12a network ends. Survey needed to confirm |
| 7 | forbidden | 6981743 v6 | `moped=no`, `traffic_sign=NL:G11`, `mofa=yes` | two G11 signs, 2022-05, 1.3 m and 3.7 m | forbidden (OSM), NDW agrees | correct |
| 8 | conflict | 635018892 v5 | `moped=no`, `traffic_sign=NL:G11`, edited 2025-07-26 (Geerweg, Nieuwkoop) | G12a with sub-sign OB505, 2025-06-23, 2.5 m | conflict, unexplained | real disagreement between two recent sources. A parallel cycle path with no moped tags runs 11.6 m away and better fits the sign bearing, so the sign may belong to it. Undecided without a survey |
| 9 | conflict | 127521919 v11 | `moped=designated`, `traffic_sign=NL:G12a` (Utrecht) | G11, 2022-03-15, 5.0 m | conflict, neighbour 816814696 (`moped=no`, G11) is 7.6 m away | probably a matching artefact: the sign sits at a junction of four cycle paths and probably belongs to the G11 path, so OSM is probably right (judged from geometry, not surveyed) |
| 10 | conflict | 573252346 v5 | `moped=designated`, no sign tag, edited 2023-10-29 (Valeriusplein, Amsterdam) | G11, 2025-09-09, 1.3 m, precise bearing 166 that fits this path | conflict, labelled neighbour (446529770 G11 path at 10 m, crosswise) | probably a real conflict with OSM outdated. The NDW record is newer and its bearing fits this path, not the neighbour, so the "neighbour" label is too generous here |

**Outcome.** All ten classifications match the raw tags and NDW records: the code does what the method
says. Data findings:

- Agreeing cases (1–5, 7) are clean.
- The one NDW-only classification (6) is plausible but sits at a junction.
- Of the three conflicts, one is probably a junction matching artefact (9), one is a genuine recent disagreement (8)
  and one is probably outdated OSM data (10).
- The "neighbour has sign's status" label is a heuristic, not proof. Case 10 shows it can hide a real
  conflict, so the fusion slice should weigh bearing precision (non-quantised NDW bearings) before
  discarding a conflict as an artefact.
- Matching at junctions is the main weakness of the simple nearest-way match. Propagation in the fusion
  slice should treat signs within a few metres of a junction as ambiguous.

### Propagated ways (fusion slice, 2026-11-14)

Five ways whose fused status comes from a propagated NDW sign, drawn with `random.Random(20261114).sample` from
the sorted ids of all 1,877 propagated ways. Checks per way:
- Tags: fetched from the OSM API at the classified version.
- Sign: read from the raw NDW download (`data/raw/ndw/*.geojson`).
- Junctions: for every node the walk covers (from the sign onwards), every OSM highway containing that node was
  listed straight from `region.osm.pbf`, independently of the fusion topology code.
- Direction: the sign's travel direction is compared with the start path's direction at the sign.

| # | Way | Raw OSM tags (relevant) | Sign (raw NDW) | Direction check | Chain (hops) | Other highways on the walked nodes | Fusion says | Verdict |
|---|---|---|---|---|---|---|---|---|
| 1 | 7429396 v11, Eisenhowerlaan | `highway=cycleway`, `oneway=yes`, no moped/sign tags | G11, bearing 0, 2022-07-18, no sub-sign; junction arm of Prins Bernhardlaan | path runs 4° at the sign | Prins Bernhardlaan → 450229985 → Albert Schweitzerbrug (2 ways) → this way (4) | footway, steps and a platform (none stop the walk); a cycle path branches at this way's exit node, where the walk stops | forbidden, 4 hops | correct per the rules |
| 2 | 60845496 v3 | `highway=cycleway`, `tunnel=yes` | G11, bearing 270, 2022-11-02 | path runs 296° | 46121644 (238 m) → this tunnel (6 m) (1) | three footways; a cycle path at the exit node | forbidden, 1 hop | correct |
| 3 | 310067475 v8 | `highway=cycleway`, `oneway=no` | G11, bearing 0, 2022-04-07, sub-sign "verboden voor motorvoertuigen" (not interpreted); handed over from the path before it | path runs 336° | 27796061 (25 m) → this way (9 m) (1) | a cycle path at the exit node | forbidden, 1 hop | correct |
| 4 | 398065174 v5, Zeepad bridge | `highway=cycleway`, `bridge=yes`, `mofa=no`, seasonal closure | G13, bearing 270, 2022-06-27 | path runs 292° | three Zeepad ways tagged forbidden in OSM → this bridge (3) | two tracks (do not stop); a cycle path at the exit node | forbidden, 3 hops | correct. The walk passes OSM-forbidden ways because they agree with the sign. `mofa=no` was not used |
| 5 | 227186791 v1, Jaagpad bridge | `highway=cycleway`, `designation=onverplicht fietspad`, `mofa=no` | G13, bearing 0, 2022-07-06, sub-sign "du niet brommen" (marked confirmed) | path runs 352° | three OSM-forbidden ways → eight short Jaagpad segments → this bridge (11) | two footways; a cycle path at the exit node | forbidden, 11 hops | correct, and OSM's own `designation=onverplicht fietspad` (G13) agrees |

**Outcome.**
- 5/5 propagated statuses reproduce from the raw data.
- In every case the sign's travel direction runs along the chain within 36°.
- Nothing that stops the walk joins any walked path before its exit node.
- None was surveyed on the ground: this checks that the code follows the method, not that the method is legally right.

An earlier version of the propagation only checked junctions at path ends. The first sample showed paths entered
across a junction partway along them (a tertiary road, a side path), so a next path with a junction partway is
now not entered at all. 64% of propagated ways are one hop from their sign.

Hand-check cases 9 and 10 from slice 1 under fusion:

- Case 10 (573252346): the G11 with precise bearing 166 now attaches to this way as expected. Correction to the
  slice 1 note: its 2025-09-09 date is `lastModifiedOn`, which moves with NDW's road-network re-link batches. The
  sign was registered on 2016-08-23, so under the sign-date rule it is older than the 2023 OSM edit. The way stays
  in `data/overrides.csv` as forbidden (not surveyed, the safe side) for the user to review.
- Case 9 (127521919): the G11 has quantised bearing 0 and stands 5.7 m from a three-arm junction. The arms leave at
  328, 57 and 150 degrees. Only 328 (this way) fits within 45 degrees, beating the next by 25, so the sign
  still attaches here. The G11 path 816814696 is not connected at that junction. OSM's explicit `moped=designated`
  wins, and the case stays in the conflict report.
