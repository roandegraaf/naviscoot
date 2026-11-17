# Coverage audit: bromfiets access on cycle paths

Generated 2026-11-17 13:27 CET by `cd data && uv run audit`. Do not edit by hand; hand-check notes live in `docs/audit/handcheck.md` and are embedded below.

## Scope and sources

- Region: 50 km around 52.156, 5.387 (Amersfoort).
- Cycle path: every OSM way with `highway=cycleway` that has at least one node inside the region; lengths are whole-way lengths.
- OSM: Geofabrik Netherlands extract `https://download.geofabrik.de/europe/netherlands-261116.osm.pbf`, Last-Modified Tue, 17 Nov 2026 00:16:41 GMT.
- NDW: verkeersborden API v5 `current-state`, one request per sign code, downloaded G11 2026-11-17T11:55:10Z, G12a 2026-11-17T11:55:16Z, G12b 2026-11-17T11:55:16Z, G13 2026-11-17T11:55:18Z. Signs with `removedOn` set are dropped.

## Method

- **OSM status** uses only `moped`, `moped:forward`, `moped:backward` and `traffic_sign*`. `moped=yes/designated/permissive/destination` is allowed, `moped=no` is forbidden; without a moped tag, `traffic_sign` NL:G12a is allowed and NL:G11 or NL:G13 is forbidden. `mofa=*` (snorfiets) is never used. A moped tag wins over a contradicting `traffic_sign` on the same way.
- **NDW match**: each G11, G12a, G12b and G13 sign is matched to the nearest cycle path segment within 20 m whose direction is within 45 degrees of the sign bearing (compared as undirected lines, so a sign for either travel direction matches). 85% of the regional NDW bearings are exactly 0, 90, 180 or 270 degrees, so for most signs this is effectively a quadrant check.
- **After NDW evidence**: OSM status is kept where OSM knows it; an OSM-unknown way takes the NDW status when all matched G11/G12a/G13 signs agree. G12b (end of moped path) is matched and counted but not used as evidence, because it says nothing on its own about which side of the sign is the moped path. This is the slice 1 method, kept unchanged so the figure stays comparable.
- **Fusion** re-attaches every G11, G12a, G12b and G13 sign and propagates it along the path network, then applies the precedence override list > explicit OSM tag > NDW (direct, then propagated) > unknown. The NDW `bearing` is the travel direction of the traffic the sign addresses: at path entrances, 10,375 bearings point into the path, 365 point out of it and 762 run across it. Details:
  - *Attachment*: a sign with a precise bearing (not a multiple of 90 degrees) goes to the nearest path within 20 m whose direction is within 20 degrees, otherwise to the nearest within 45 degrees. If a cycle path junction (three or more path arms) lies within 8 m, the sign goes to the arm that leaves the junction in its travel direction, but only when that arm is within 20 (precise) or 45 (quantised) degrees and beats the next arm by at least 15 degrees; otherwise the sign is ambiguous and gives no evidence. A sign less than 5 m before the end of its path, in its travel direction, is handed to the next path when exactly one path continues there and no road joins.
  - *Propagation*: from the attached path, the status is walked forward in the sign's travel direction over connected cycle paths. It stops at a junction with a road (any motor road, including `service` except driveways and parking aisles; footways, paths and tracks do not stop it) or with another cycle path: at the end of a path, or inside the signed path ahead of the sign. A next path that has such a junction partway along it is not entered, because status is per whole way and part of it lies beyond the junction. It also stops at a dead end; before a path that carries its own G11/G12a/G12b/G13 sign; after a path whose explicit OSM tag says the opposite; after a path with a G12b for the same travel direction; at a closed loop; or after 5 km. Status is per whole way.
  - *NDW verdict per way*: direct signs beat propagated ones; disagreeing signs of the stronger kind leave the way 'mixed' (unknown).
  - *Supplementary signs*: 'onleesbaar' (unreadable) removes the sign as evidence (it still stops propagation). On a G11/G13, a text matching 'snor... niet', 'niet brommen' or 'naar/op de rijbaan' marks the sign as confirmed; this is shown in the conflict report and does not change precedence. 'speed-pedelecs toegestaan' has no effect: it exempts speed pedelecs only, not other mopeds. OB505 and OB502 are not interpreted: their meaning could not be verified (see below).
  - *Precedence* (user decision, 2026-11-14): override list > NDW sign that is newer than the OSM edit and attached unambiguously > explicit OSM tag > NDW (direct, then propagated) > unknown. *Unambiguous* (the orchestrator's reading of the user's "if trustworthy") means the sign is on its matched path (not a junction arm or hand-over), at most 10 m from it, with no other fitting cycle path and no cycle path junction within 20 m, and without an OB505/OB502 sub-sign. Road junctions don't count: nearly every sign stands right after one. Propagated NDW never beats OSM. The NDW date is the newest of `validatedOn`, `placedOn` and `registeredOn`. `lastModifiedOn` is not used, because it moves with NDW's road-network re-link batches (2,886 regional records on 2025-09-09 with NWB version 2025-09-01). The OSM date is the way's own timestamp. The override list is `data/overrides.csv`.

## Cycle path status from OSM alone

| Status | Ways | Length (km) | Share of length |
|---|---:|---:|---:|
| allowed | 17,505 | 3,113.4 | 32.4% |
| forbidden | 28,685 | 4,394.1 | 45.7% |
| unknown | 26,392 | 2,115.8 | 22.0% |
| **total** | **72,582** | **9,623.3** | 100% |

## Cycle path status after adding NDW evidence

| Status | Ways | Length (km) | Share of length |
|---|---:|---:|---:|
| allowed | 19,014 | 3,282.5 | 34.1% |
| forbidden | 35,820 | 5,163.8 | 53.7% |
| unknown | 17,748 | 1,177.0 | 12.2% |
| **total** | **72,582** | **9,623.3** | 100% |

Unknown length drops from 2,115.8 km to 1,177.0 km (938.9 km resolved by NDW).

## Cycle path status after fusion

| Status | Ways | Length (km) | Share of length |
|---|---:|---:|---:|
| allowed | 18,995 | 3,297.0 | 34.3% |
| forbidden | 35,783 | 5,218.7 | 54.2% |
| unknown | 17,804 | 1,107.6 | 11.5% |
| **total** | **72,582** | **9,623.3** | 100% |

### Unknown cycle-path length by stage

| Stage | Unknown ways | Unknown length (km) | Share of length |
|---|---:|---:|---:|
| OSM alone | 26,392 | 2,115.8 | 22.0% |
| After NDW point evidence (slice 1 method) | 17,748 | 1,177.0 | 12.2% |
| After fusion | 17,804 | 1,107.6 | 11.5% |

Unknown length goes from 1,177.0 km (slice 1) to 1,107.6 km. Against the slice 1 method:

| Change | Ways | Length (km) |
|---|---:|---:|
| Newly resolved by a direct sign (re-attachment, hand-over to the next path) | 469 | 28.4 |
| Newly resolved by propagation | 1,805 | 103.2 |
| Resolved in slice 1 but unknown after fusion (sign now ambiguous or attached elsewhere) | 2,330 | 62.3 |
| ... of which NDW signs now disagree on the way (mixed) | 9 | 1.3 |
| Resolved in both, but to the opposite status | 3 | 0.0 |

### Where the fused status comes from

| Source | Ways | Length (km) | ... of which unknown in OSM (km) |
|---|---:|---:|---:|
| override list | 1 | 0.1 | 0.0 |
| explicit OSM tag | 46,173 | 7,503.9 | 0.0 |
| NDW sign newer than the OSM tag | 16 | 3.6 | 0.0 |
| NDW sign on the way | 6,712 | 902.3 | 902.3 |
| NDW sign propagated from another way | 1,876 | 105.9 | 105.9 |
| none (unknown) | 17,804 | 1,107.6 | 1,107.6 |

Propagated ways by distance from the sign (in ways): 1 hop 1,206, 2 hops 445, 3 hops 127, 4 hops 46, 5 hops 19, 6 hops 11, more 22.

### Sign attachment

| Sign | In region | On its matched path | Junction arm | Handed to next path | Ambiguous at cycle junction | No path fits | Unreadable (no evidence) | Confirmed by sub-sign |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| G11 | 31,822 | 19,969 | 5,082 | 621 | 3,950 | 2,200 | 410 | 1,392 |
| G12a | 15,015 | 9,501 | 2,161 | 344 | 2,071 | 938 | 23 | 0 |
| G12b | 1,223 | 960 | 82 | 22 | 22 | 137 | 2 | 0 |
| G13 | 4,123 | 2,904 | 432 | 107 | 175 | 505 | 32 | 158 |

OB505 and OB502 (OB505 on 210 attached signs, OB502 on 13 attached signs) are not interpreted. Their meaning was looked up on 2026-11-14 in the OSM wiki list of Dutch sub-signs (it lists OB51 to OB66 and OB504, 'arrows down-left and down-right', but not OB502 or OB505), the OSM community forum (OB505 appears under a G12a, undefined) and Noord-Brabant sign drawings (exb-2019-6446: sizes only). No catalogue entry with their meaning was reachable, so the main sign's meaning stands. They sit in the arrow sub-sign family next to OB504, which would not change who may use the path, but that is an inference, not a lookup.

## Override list (1 entry)

`data/overrides.csv` (way id, status, reason, date) is maintained by hand and beats every other source.

| Way | Override | OSM says | NDW says | Fused | Reason |
|---|---|---|---|---|---|
| [573252346](https://www.openstreetmap.org/way/573252346) v5 | forbidden (2026-11-14) | allowed (2023-10-29) | forbidden | **forbidden** | Valeriusplein, Amsterdam. Not surveyed. OSM has moped=designated (way v5, edited 2023-10-29); NDW has a G11 registered 2016-08-23 (record last modified 2025-09-09 in an NWB re-link batch) whose precise bearing (166) fits this path. Kept forbidden as the safe side until surveyed; review. |

## Unknown cycle paths and NDW

| | Ways | Length (km) |
|---|---:|---:|
| Unknown in OSM | 26,392 | 2,115.8 |
| ... with a matched G11/G12a/G13 sign (distance + bearing) | 8,783 | 973.1 |
| ... resolved by NDW (all matched signs agree) | 8,644 | 938.9 |
| ... matched signs disagree (G12a and G11/G13 on one way) | 139 | 34.2 |
| ... with any of the four signs within 20 m, ignoring bearing | 15,310 | 1,311.7 |
| **Remain unknown after NDW** | **17,748** | **1,177.0** |

Tags on the cycle paths that remain unknown (not used for classification; inputs for the fusion slice):

| Tag present | Ways | Length (km) |
|---|---:|---:|
| `mofa=*` | 574 | 36.7 |
| `motor_vehicle=no` | 134 | 10.4 |
| `vehicle=no` | 5 | 0.3 |
| `access=no/private` | 128 | 10.6 |
| `bicycle=designated` | 417 | 32.3 |
| `traffic_sign=* (other than G11/G12a/G13)` | 135 | 28.4 |
| none of these | 16,439 | 1,064.5 |

## NDW sign matching

| Sign | In region | Matched (distance + bearing) | Matched (distance only) | No cycle path within 20 m |
|---|---:|---:|---:|---:|
| G11 | 31,822 | 29,624 | 30,950 | 872 |
| G12a | 15,015 | 14,080 | 14,707 | 308 |
| G12b | 1,223 | 1,086 | 1,160 | 63 |
| G13 | 4,123 | 3,619 | 3,882 | 241 |

Nearest other highway within 20 m for signs without a cycle path nearby: `footway` 406, `residential` 368, `unclassified` 196, `tertiary` 123, `path` 100, `service` 66, `secondary` 58, `pedestrian` 51; nothing within 20 m: 13. For 127 of these 1,484 signs the nearest way carries `cycleway*=track` or `lane`, i.e. a cycle path mapped on the road rather than as a separate way.

## NDW sub-signs and exemptions (slice 1 point matching)

Counts from the slice 1 matching, where every G11 and G13 is scored forbidden and every G12a allowed. Fusion interprets the sub-signs as described in the method. A *deviating exemption* is a G11/G13 whose structured `conditions.exemptions` include `moped`, or a G12a whose exemptions do not.

| | Matched G11/G12a/G13 signs | Conflict pairs | NDW-resolved ways (km) |
|---|---:|---:|---:|
| has a supplementary sign with a code or text | 3,571 | 90 | 940 (112.4) |
| has a deviating exemption | 0 | 0 | 0 (0.0) |

Most common supplementary texts on matched signs: "snorfietsen niet toegestaan" 1,436, "onleesbaar" 543, "ob505" 220, "dus niet brommen" 154, "speed-pedelecs toegestaan" 146, "ob502" 81, "uitgezonderd bestemmingsverkeer" 53, "snorfietsen niet  toegestaan" 49.

## Conflicts between OSM and NDW

After fusion, OSM and NDW disagree on 702 ways. Every one is listed with both dates, the winner and the reason in [`conflicts.md`](conflicts.md).

| OSM says | NDW says | NDW kind | Ways | NDW newer | Confirmed by sub-sign | Won by NDW | Won by override |
|---|---|---|---:|---:|---:|---:|---:|
| allowed | forbidden | direct | 478 | 49 | 21 | 11 | 1 |
| allowed | forbidden | propagated | 19 | 3 | 1 | 0 | 0 |
| forbidden | allowed | direct | 199 | 14 | 0 | 5 | 0 |
| forbidden | allowed | propagated | 6 | 0 | 0 | 0 | 0 |

### Newer NDW against older OSM: what the rule did

NDW sign dates: 1,036 of 50,960 G11/G12a/G13 records have `validatedOn`, 1,077 have `placedOn`, and 0 have none of these three dates. Undated records never win on recency.

| Outcome (conflicts not settled by an override) | Ways | Length (km) |
|---|---:|---:|
| Resolved in NDW's favour | 16 | 3.6 |
| Left in the conflict report: NDW is newer but its sign attachment is ambiguous | 47 | 5.0 |
| Left in the conflict report: OSM edit is newer than the NDW sign | 613 | 101.8 |
| Left in the conflict report: NDW status is propagated from another path | 25 | 1.5 |
| Left in the conflict report: NDW record has no placed, validated or registered date | 0 | 0.0 |

Why attached signs are not unambiguous (all attached signs, not only conflicts): another fitting cycle path within 20 m 12,995, sign attached as junction arm 7,757, sign more than 10 m from the path 2,100, cycle path junction within 20 m 2,040, sign attached as handed over 1,094, sign carries a sub-sign of unverified meaning (OB505/OB502) 175.

For comparison, the slice 1 point matching found 1,583 sign-way conflict pairs on 1,270 ways. Fusion has fewer because signs at cycle path junctions are re-attached by direction or dropped as ambiguous.

## Ways where OSM contradicts itself (95)

`moped=*` and `traffic_sign=*` on the same way point in different directions; the moped tag was used.

- [6889653](https://www.openstreetmap.org/way/6889653): moped=`designated`, traffic_sign=`NL:G11`
- [6944502](https://www.openstreetmap.org/way/6944502): moped=`destination`, traffic_sign=`NL:G13;OB(uitgezonderd bestemmingsverkeer)`
- [7010789](https://www.openstreetmap.org/way/7010789): moped=`no`, traffic_sign=`NL:G12a`
- [7024033](https://www.openstreetmap.org/way/7024033): moped=`designated`, traffic_sign=`NL:G11`
- [7027035](https://www.openstreetmap.org/way/7027035): moped=`designated`, traffic_sign=`NL:G11`
- [7030389](https://www.openstreetmap.org/way/7030389): moped=`designated`, traffic_sign=`NL:G11`
- [7035636](https://www.openstreetmap.org/way/7035636): moped=`destination`, traffic_sign=`NL:G11`
- [7061461](https://www.openstreetmap.org/way/7061461): moped=`destination`, traffic_sign=`NL:G13`
- [7352637](https://www.openstreetmap.org/way/7352637): moped=`destination`, traffic_sign=`NL:G11`
- [10571056](https://www.openstreetmap.org/way/10571056): moped=`no`, traffic_sign=`NL:G12a`
- [22994729](https://www.openstreetmap.org/way/22994729): moped=`designated`, traffic_sign=`NL:G13`
- [24202856](https://www.openstreetmap.org/way/24202856): moped=`no`, traffic_sign=`NL:G12a`
- [33435389](https://www.openstreetmap.org/way/33435389): moped=`no`, traffic_sign=`NL:G12a`
- [34036592](https://www.openstreetmap.org/way/34036592): moped=`designated`, traffic_sign=`NL:G11`
- [43998795](https://www.openstreetmap.org/way/43998795): moped=`no`, traffic_sign=`NL:G12a`
- [44003492](https://www.openstreetmap.org/way/44003492): moped=`designated`, traffic_sign=`NL:G11`
- [44367588](https://www.openstreetmap.org/way/44367588): moped=`designated`, traffic_sign=`NL:G11`
- [45420920](https://www.openstreetmap.org/way/45420920): moped=`designated`, traffic_sign=`NL:G11`
- [55241369](https://www.openstreetmap.org/way/55241369): moped=`designated`, traffic_sign=`NL:G11`
- [71835057](https://www.openstreetmap.org/way/71835057): moped=`destination`, traffic_sign=`NL:G13;OB(uitgezonderd bestemmingsverkeer)`
- [109906126](https://www.openstreetmap.org/way/109906126): moped=`designated`, traffic_sign=`NL:G11`
- [111251832](https://www.openstreetmap.org/way/111251832): moped=`no`, traffic_sign=`NL:G12a`
- [118601065](https://www.openstreetmap.org/way/118601065): moped=`designated`, traffic_sign=`NL:G11`
- [118908487](https://www.openstreetmap.org/way/118908487): moped=`designated`, traffic_sign=`NL:G11`
- [135855992](https://www.openstreetmap.org/way/135855992): moped=`designated`, traffic_sign=`NL:G11`
- [143215071](https://www.openstreetmap.org/way/143215071): moped=`yes`, traffic_sign=`NL:G11`
- [144988301](https://www.openstreetmap.org/way/144988301): moped=`no`, traffic_sign=`NL:G12a`
- [146372249](https://www.openstreetmap.org/way/146372249): moped=`yes`, traffic_sign=`NL:G11`
- [157529069](https://www.openstreetmap.org/way/157529069): moped=`yes`, traffic_sign=`NL:G11`
- [161115426](https://www.openstreetmap.org/way/161115426): moped=`destination`, traffic_sign=`NL:G13`
- [169464530](https://www.openstreetmap.org/way/169464530): moped=`designated`, traffic_sign=`NL:G11`
- [191028802](https://www.openstreetmap.org/way/191028802): moped=`no`, traffic_sign=`NL:G12a`
- [219249269](https://www.openstreetmap.org/way/219249269): moped=`destination`, traffic_sign=`NL:G13`
- [221399727](https://www.openstreetmap.org/way/221399727): moped=`designated`, traffic_sign=`NL:G11`
- [221399729](https://www.openstreetmap.org/way/221399729): moped=`designated`, traffic_sign=`NL:G11`
- [226577211](https://www.openstreetmap.org/way/226577211): moped=`no`, traffic_sign=`NL:G12a`
- [252980034](https://www.openstreetmap.org/way/252980034): moped=`designated`, traffic_sign=`NL:G13`
- [259649631](https://www.openstreetmap.org/way/259649631): moped=`no`, traffic_sign=`NL:G12a`
- [328016982](https://www.openstreetmap.org/way/328016982): moped=`yes`, traffic_sign=`NL:G13`
- [336732871](https://www.openstreetmap.org/way/336732871): moped=`designated`, traffic_sign=`NL:G11`
- [355461278](https://www.openstreetmap.org/way/355461278): moped=`None`, traffic_sign=`NL:G11`
- [449836157](https://www.openstreetmap.org/way/449836157): moped=`designated`, traffic_sign=`NL:G11`
- [534053013](https://www.openstreetmap.org/way/534053013): moped=`yes`, traffic_sign=`NL:G11`
- [542662601](https://www.openstreetmap.org/way/542662601): moped=`designated`, traffic_sign=`NL:G11`
- [605874100](https://www.openstreetmap.org/way/605874100): moped=`designated`, traffic_sign=`NL:G11`
- [627362121](https://www.openstreetmap.org/way/627362121): moped=`no`, traffic_sign=`NL:G12a`
- [646225853](https://www.openstreetmap.org/way/646225853): moped=`designated`, traffic_sign=`NL:G11`
- [676280778](https://www.openstreetmap.org/way/676280778): moped=`designated`, traffic_sign=`NL:G13`
- [676284209](https://www.openstreetmap.org/way/676284209): moped=`designated`, traffic_sign=`NL:G13`
- [689589150](https://www.openstreetmap.org/way/689589150): moped=`designated`, traffic_sign=`NL:G11`
- ... and 45 more

## Hand check

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

## Limitations

- Cycle tracks mapped as a tag on the road (`cycleway=track`) are not cycle path ways and are not counted.
- Status is per whole OSM way. A sign in the middle of a way, or at a junction inside a way, classifies the whole way, also the part behind the sign.
- Propagation stops at every branching junction, so a moped path network with many side branches is only partly covered from one sign. Signs at cycle path junctions with a quantised bearing are often ambiguous and give no evidence.
- Only the supplementary texts listed in the method are interpreted. OB505 and OB502 are not.
- The override list holds what the user decided; an override without a survey is marked as such in its reason.
- OSM last-modified is the way's own timestamp; a node move does not change it.
- The NDW API sends no ETag, so `fetch` re-downloads NDW after 20 hours instead of checking for changes.
