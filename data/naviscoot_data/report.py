import json
import time
from collections import Counter
from pathlib import Path

import requests

from . import fuse, paths
from .classify import ALLOWED, FORBIDDEN, SIGN_STATUS, UNKNOWN

STATUSES = (ALLOWED, FORBIDDEN, UNKNOWN)
LEAFLET_VERSION = "1.9.4"
LEAFLET_BASE = f"https://cdnjs.cloudflare.com/ajax/libs/leaflet/{LEAFLET_VERSION}"
HINT_TAGS = (
    ("mofa=*", lambda t: "mofa" in t),
    ("motor_vehicle=no", lambda t: t.get("motor_vehicle") == "no"),
    ("vehicle=no", lambda t: t.get("vehicle") == "no"),
    ("access=no/private", lambda t: t.get("access") in ("no", "private")),
    ("bicycle=designated", lambda t: t.get("bicycle") == "designated"),
    ("traffic_sign=* (other than G11/G12a/G13)", lambda t: "traffic_sign" in t),
)


def _moped_exempt(sign) -> bool:
    exemptions = (sign.props.get("conditions") or {}).get("exemptions") or []
    return any("moped" in (e.get("vehicleType") or []) for e in exemptions)


def deviating_exemption(sign) -> bool:
    if sign.code == "G12a":
        return not _moped_exempt(sign)
    return sign.code in ("G11", "G13") and _moped_exempt(sign)


def has_supplementary(sign) -> bool:
    return any(x.get("signCode") != "OTHER" or (x.get("text") or "").strip() for x in sign.props.get("supplementarySigns") or [])


def _km(m: float) -> str:
    return f"{m / 1000:,.1f}"


def _split(ways, key) -> dict[str, tuple[int, float]]:
    out = {s: [0, 0.0] for s in STATUSES}
    for w in ways:
        out[key(w)][0] += 1
        out[key(w)][1] += w.length_m
    return {s: (n, m) for s, (n, m) in out.items()}


def _split_table(split: dict[str, tuple[int, float]]) -> list[str]:
    total_n = sum(n for n, _ in split.values())
    total_m = sum(m for _, m in split.values())
    rows = ["| Status | Ways | Length (km) | Share of length |", "|---|---:|---:|---:|"]
    for s in STATUSES:
        n, m = split[s]
        rows.append(f"| {s} | {n:,} | {_km(m)} | {100 * m / total_m:.1f}% |")
    rows.append(f"| **total** | **{total_n:,}** | **{_km(total_m)}** | 100% |")
    return rows


def _way_link(way_id: int) -> str:
    return f"[{way_id}](https://www.openstreetmap.org/way/{way_id})"


def write_report(ctx: dict, out: Path, handcheck: Path) -> None:
    ways = list(ctx["cycleways"].values())
    signs = ctx["signs"]
    conflicts = ctx["conflicts"]
    p = ctx["params"]
    src = ctx["sources"]

    before = _split(ways, lambda w: w.osm_status)
    after = _split(ways, lambda w: w.final_status)
    unknown_osm = [w for w in ways if w.osm_status == UNKNOWN]
    unknown_with_sign = [w for w in unknown_osm if w.signs]
    unknown_resolved = [w for w in unknown_osm if w.ndw_status in (ALLOWED, FORBIDDEN)]
    unknown_mixed = [w for w in unknown_osm if w.ndw_status == "mixed"]
    unknown_any_nearby = [w for w in unknown_osm if w.nearby_any]
    unknown_after = [w for w in ways if w.final_status == UNKNOWN]
    resolved_km = sum(w.length_m for w in unknown_resolved)
    matched_status = [s for s in signs if s.code in ("G11", "G12a", "G13") and s.best_cycleway]
    by_sign = {s.id: s for s in signs}
    quantised_pct = 100 * sum(1 for s in signs if s.bearing in (0, 90, 180, 270)) / len(signs)
    cal = ctx["fusion"]["calibration"]
    calibration = (f"{cal['aligned']:,} bearings point into the path, {cal['opposite']:,} point out of it and"
                   f" {cal['across']:,} run across it.")

    lines = [
        "# Coverage audit: bromfiets access on cycle paths",
        "",
        f"Generated {time.strftime('%Y-%m-%d %H:%M %Z')} by `cd data && uv run audit`. Do not edit by hand;"
        " hand-check notes live in `docs/audit/handcheck.md` and are embedded below.",
        "",
        "## Scope and sources",
        "",
        f"- Region: {p['radius_km']:.0f} km around {p['center'][0]}, {p['center'][1]} (Amersfoort).",
        "- Cycle path: every OSM way with `highway=cycleway` that has at least one node inside the region;"
        " lengths are whole-way lengths.",
        f"- OSM: Geofabrik Netherlands extract `{src['osm'].get('url', '?')}`, Last-Modified"
        f" {src['osm'].get('last_modified', '?')}.",
        "- NDW: verkeersborden API v5 `current-state`, one request per sign code, downloaded "
        + ", ".join(f"{c} {m.get('downloaded_at', '?')}" for c, m in src["ndw"].items())
        + ". Signs with `removedOn` set are dropped.",
        "",
        "## Method",
        "",
        "- **OSM status** uses only `moped`, `moped:forward`, `moped:backward` and `traffic_sign*`."
        " `moped=yes/designated/permissive/destination` is allowed, `moped=no` is forbidden; without a moped tag,"
        " `traffic_sign` NL:G12a is allowed and NL:G11 or NL:G13 is forbidden. `mofa=*` (snorfiets) is never used."
        " A moped tag wins over a contradicting `traffic_sign` on the same way.",
        f"- **NDW match**: each G11, G12a, G12b and G13 sign is matched to the nearest cycle path segment within"
        f" {p['match_distance_m']:.0f} m whose direction is within {p['axis_tolerance_deg']:.0f} degrees of the"
        " sign bearing (compared as undirected lines, so a sign for either travel direction matches)."
        f" {quantised_pct:.0f}% of the regional NDW bearings are exactly 0, 90, 180 or 270 degrees, so for most"
        " signs this is effectively a quadrant check.",
        "- **After NDW evidence**: OSM status is kept where OSM knows it; an OSM-unknown way takes the NDW status when"
        " all matched G11/G12a/G13 signs agree. G12b (end of moped path) is matched and counted but not used as"
        " evidence, because it says nothing on its own about which side of the sign is the moped path."
        " This is the slice 1 method, kept unchanged so the figure stays comparable.",
        "- **Fusion** re-attaches every G11, G12a, G12b and G13 sign and propagates it along the path network,"
        " then applies the precedence override list > explicit OSM tag > NDW (direct, then propagated) > unknown."
        " The NDW `bearing` is the travel direction of the traffic the sign addresses: at path entrances,"
        f" {calibration} Details:",
        f"  - *Attachment*: a sign with a precise bearing (not a multiple of 90 degrees) goes to the nearest path"
        f" within {p['match_distance_m']:.0f} m whose direction is within {fuse.PRECISE_AXIS_TOLERANCE_DEG:.0f} degrees,"
        f" otherwise to the nearest within {fuse.MATCH_AXIS_TOLERANCE_DEG:.0f} degrees. If a cycle path junction"
        f" (three or more path arms) lies within {fuse.CYCLE_JUNCTION_M:.0f} m, the sign goes to the arm that leaves"
        f" the junction in its travel direction, but only when that arm is within {fuse.PRECISE_AXIS_TOLERANCE_DEG:.0f}"
        f" (precise) or {fuse.ARM_TOLERANCE_DEG:.0f} (quantised) degrees and beats the next arm by at least"
        f" {fuse.ARM_MARGIN_DEG:.0f} degrees; otherwise the sign is ambiguous and gives no evidence. A sign less than"
        f" {fuse.END_HANDOVER_M:.0f} m before the end of its path, in its travel direction, is handed to the next path"
        " when exactly one path continues there and no road joins.",
        "  - *Propagation*: from the attached path, the status is walked forward in the sign's travel direction over"
        " connected cycle paths. It stops at a junction with a road (any motor road, including `service` except"
        " driveways and parking aisles; footways, paths and tracks do not stop it) or with another cycle path: at the"
        " end of a path, or inside the signed path ahead of the sign. A next path that has such a junction partway"
        " along it is not entered, because status is per whole way and part of it lies beyond the junction."
        " It also stops at a dead end; before a path that carries its own"
        " G11/G12a/G12b/G13 sign; after a path whose explicit OSM tag says the opposite; after a path with a G12b for"
        f" the same travel direction; at a closed loop; or after {fuse.MAX_PROPAGATION_M / 1000:.0f} km."
        " Status is per whole way.",
        "  - *NDW verdict per way*: direct signs beat propagated ones; disagreeing signs of the stronger kind leave"
        " the way 'mixed' (unknown).",
        "  - *Supplementary signs*: 'onleesbaar' (unreadable) removes the sign as evidence (it still stops"
        " propagation). On a G11/G13, a text matching 'snor... niet', 'niet brommen' or 'naar/op de rijbaan' marks the"
        " sign as confirmed; this is shown in the conflict report and does not change precedence."
        " 'speed-pedelecs toegestaan' has no effect: it exempts speed pedelecs only, not other mopeds."
        " OB505 and OB502 are not interpreted: their meaning could not be verified (see below).",
        "  - *Precedence* (user decision, 2026-11-14): override list > NDW sign that is newer than the OSM edit and"
        " attached unambiguously > explicit OSM tag > NDW (direct, then propagated) > unknown. *Unambiguous* (the"
        " orchestrator's reading of the user's \"if trustworthy\") means the sign is on its matched path (not a"
        f" junction arm or hand-over), at most {fuse.TRUST_MAX_DISTANCE_M:.0f} m from it, with no other fitting cycle"
        f" path and no cycle path junction within {fuse.SNAP_TOLERANCE_M:.0f} m, and without an OB505/OB502 sub-sign. Road junctions don't count: nearly"
        " every sign stands right after one. Propagated NDW never beats OSM. The NDW date is the newest of"
        " `validatedOn`, `placedOn` and `registeredOn`. `lastModifiedOn` is not used, because it moves with NDW's"
        " road-network re-link batches (2,886 regional records on 2025-09-09 with NWB version 2025-09-01). The OSM"
        " date is the way's own timestamp. The override list is `data/overrides.csv`.",
        "",
        "## Cycle path status from OSM alone",
        "",
        *_split_table(before),
        "",
        "## Cycle path status after adding NDW evidence",
        "",
        *_split_table(after),
        "",
        f"Unknown length drops from {_km(before[UNKNOWN][1])} km to {_km(after[UNKNOWN][1])} km"
        f" ({_km(resolved_km)} km resolved by NDW).",
        "",
        *_fusion_sections(ctx, ways, before, after),
        "## Unknown cycle paths and NDW",
        "",
        "| | Ways | Length (km) |",
        "|---|---:|---:|",
        f"| Unknown in OSM | {len(unknown_osm):,} | {_km(sum(w.length_m for w in unknown_osm))} |",
        f"| ... with a matched G11/G12a/G13 sign (distance + bearing) | {len(unknown_with_sign):,}"
        f" | {_km(sum(w.length_m for w in unknown_with_sign))} |",
        f"| ... resolved by NDW (all matched signs agree) | {len(unknown_resolved):,} | {_km(resolved_km)} |",
        f"| ... matched signs disagree (G12a and G11/G13 on one way) | {len(unknown_mixed):,}"
        f" | {_km(sum(w.length_m for w in unknown_mixed))} |",
        f"| ... with any of the four signs within {p['match_distance_m']:.0f} m, ignoring bearing | {len(unknown_any_nearby):,}"
        f" | {_km(sum(w.length_m for w in unknown_any_nearby))} |",
        f"| **Remain unknown after NDW** | **{len(unknown_after):,}** | **{_km(sum(w.length_m for w in unknown_after))}** |",
        "",
        "Tags on the cycle paths that remain unknown (not used for classification; inputs for the fusion slice):",
        "",
        "| Tag present | Ways | Length (km) |",
        "|---|---:|---:|",
    ]
    for label, pred in HINT_TAGS:
        hit = [w for w in unknown_after if pred(w.tags)]
        lines.append(f"| `{label}` | {len(hit):,} | {_km(sum(w.length_m for w in hit))} |")
    none = [w for w in unknown_after if not any(pred(w.tags) for _, pred in HINT_TAGS)]
    lines.append(f"| none of these | {len(none):,} | {_km(sum(w.length_m for w in none))} |")

    lines += [
        "",
        "## NDW sign matching",
        "",
        f"| Sign | In region | Matched (distance + bearing) | Matched (distance only) | No cycle path within {p['match_distance_m']:.0f} m |",
        "|---|---:|---:|---:|---:|",
    ]
    for code in ("G11", "G12a", "G12b", "G13"):
        cs = [s for s in signs if s.code == code]
        lines.append(
            f"| {code} | {len(cs):,} | {sum(1 for s in cs if s.best_cycleway):,}"
            f" | {sum(1 for s in cs if s.best_cycleway_any_bearing):,}"
            f" | {sum(1 for s in cs if not s.best_cycleway_any_bearing):,} |"
        )
    unmatched = [s for s in signs if not s.best_cycleway_any_bearing]
    other = Counter(s.best_other[1] for s in unmatched if s.best_other)
    lines += [
        "",
        f"Nearest other highway within {p['match_distance_m']:.0f} m for signs without a cycle path nearby: "
        + ", ".join(f"`{k}` {v:,}" for k, v in other.most_common(8))
        + f"; nothing within {p['match_distance_m']:.0f} m: {sum(1 for s in unmatched if not s.best_other):,}."
        f" For {sum(1 for s in unmatched if s.best_other and s.best_other[3]):,} of these {len(unmatched):,} signs the"
        " nearest way carries `cycleway*=track` or `lane`, i.e. a cycle path mapped on the road rather than as"
        " a separate way.",
        "",
        "## NDW sub-signs and exemptions (slice 1 point matching)",
        "",
        "Counts from the slice 1 matching, where every G11 and G13 is scored forbidden and every G12a allowed."
        " Fusion interprets the sub-signs as described in the method. A *deviating exemption* is a G11/G13 whose structured"
        " `conditions.exemptions` include `moped`, or a G12a whose exemptions do not.",
        "",
        "| | Matched G11/G12a/G13 signs | Conflict pairs | NDW-resolved ways (km) |",
        "|---|---:|---:|---:|",
        *[
            f"| {label} | {sum(1 for s in matched_status if pred(s)):,}"
            f" | {sum(1 for c in conflicts if pred(by_sign[c['sign_id']])):,}"
            f" | {sum(1 for w in unknown_resolved if any(pred(by_sign[x]) for x in w.signs)):,}"
            f" ({_km(sum(w.length_m for w in unknown_resolved if any(pred(by_sign[x]) for x in w.signs)))}) |"
            for label, pred in (
                ("has a supplementary sign with a code or text", has_supplementary),
                ("has a deviating exemption", deviating_exemption),
            )
        ],
        "",
        "Most common supplementary texts on matched signs: "
        + ", ".join(
            f"\"{t}\" {n:,}"
            for t, n in Counter(
                (x.get("text") or x.get("signCode") or "").strip().lower()
                for s in matched_status
                for x in s.props.get("supplementarySigns") or []
                if x.get("signCode") != "OTHER" or (x.get("text") or "").strip()
            ).most_common(8)
        )
        + ".",
        "",
        "## Conflicts between OSM and NDW",
        "",
        *_conflict_summary(ctx),
        "",
    ]

    disagreements = ctx["disagreements"]
    lines += [
        f"## Ways where OSM contradicts itself ({len(disagreements)})",
        "",
        "`moped=*` and `traffic_sign=*` on the same way point in different directions; the moped tag was used.",
        "",
    ]
    for w in sorted(disagreements, key=lambda w: w.id)[:50]:
        lines.append(f"- {_way_link(w.id)}: moped=`{w.tags.get('moped')}`, traffic_sign=`{w.tags.get('traffic_sign')}`")
    if len(disagreements) > 50:
        lines.append(f"- ... and {len(disagreements) - 50} more")

    lines += ["", "## Hand check", ""]
    if handcheck.exists():
        lines.append(handcheck.read_text().strip())
    else:
        lines.append("Not done yet. The sample to check is in `data/build/handcheck_sample.json`.")
    lines += [
        "",
        "## Limitations",
        "",
        "- Cycle tracks mapped as a tag on the road (`cycleway=track`) are not cycle path ways and are not counted.",
        "- Status is per whole OSM way. A sign in the middle of a way, or at a junction inside a way, classifies the"
        " whole way, also the part behind the sign.",
        "- Propagation stops at every branching junction, so a moped path network with many side branches is only"
        " partly covered from one sign. Signs at cycle path junctions with a quantised bearing are often ambiguous"
        " and give no evidence.",
        "- Only the supplementary texts listed in the method are interpreted. OB505 and OB502 are not.",
        "- The override list holds what the user decided; an override without a survey is marked as such in its"
        " reason.",
        "- OSM last-modified is the way's own timestamp; a node move does not change it.",
        "- The NDW API sends no ETag, so `fetch` re-downloads NDW after 20 hours instead of checking for changes.",
        "",
    ]
    out.write_text("\n".join(lines))


def _fusion_sections(ctx: dict, ways: list, before: dict, after: dict) -> list[str]:
    fz = ctx["fusion"]
    fused = fz["fused"]
    signs = ctx["signs"]
    overrides = ctx["overrides"]
    fused_split = _split(ways, lambda w: fused[w.id].status)

    def km_of(pred) -> tuple[int, float]:
        hit = [w for w in ways if pred(w)]
        return len(hit), sum(w.length_m for w in hit)

    lines = [
        "## Cycle path status after fusion",
        "",
        *_split_table(fused_split),
        "",
        "### Unknown cycle-path length by stage",
        "",
        "| Stage | Unknown ways | Unknown length (km) | Share of length |",
        "|---|---:|---:|---:|",
    ]
    total = sum(m for _, m in before.values())
    for label, split in (("OSM alone", before), ("After NDW point evidence (slice 1 method)", after),
                         ("After fusion", fused_split)):
        n, m = split[UNKNOWN]
        lines.append(f"| {label} | {n:,} | {_km(m)} | {100 * m / total:.1f}% |")

    gained_direct = km_of(lambda w: w.final_status == UNKNOWN and fused[w.id].source == fuse.SOURCE_NDW_DIRECT)
    gained_prop = km_of(lambda w: w.final_status == UNKNOWN and fused[w.id].source == fuse.SOURCE_NDW_PROPAGATED)
    lost = km_of(lambda w: w.final_status != UNKNOWN and fused[w.id].status == UNKNOWN)
    lost_mixed = km_of(lambda w: w.final_status != UNKNOWN and fused[w.id].status == UNKNOWN
                       and fused[w.id].ndw_status == "mixed")
    point_but_changed = km_of(lambda w: w.osm_status == UNKNOWN and w.final_status in (ALLOWED, FORBIDDEN)
                              and fused[w.id].status in (ALLOWED, FORBIDDEN) and fused[w.id].status != w.final_status)
    lines += [
        "",
        f"Unknown length goes from {_km(after[UNKNOWN][1])} km (slice 1) to {_km(fused_split[UNKNOWN][1])} km. Against"
        " the slice 1 method:",
        "",
        "| Change | Ways | Length (km) |",
        "|---|---:|---:|",
        f"| Newly resolved by a direct sign (re-attachment, hand-over to the next path) | {gained_direct[0]:,}"
        f" | {_km(gained_direct[1])} |",
        f"| Newly resolved by propagation | {gained_prop[0]:,} | {_km(gained_prop[1])} |",
        f"| Resolved in slice 1 but unknown after fusion (sign now ambiguous or attached elsewhere) | {lost[0]:,}"
        f" | {_km(lost[1])} |",
        f"| ... of which NDW signs now disagree on the way (mixed) | {lost_mixed[0]:,} | {_km(lost_mixed[1])} |",
        f"| Resolved in both, but to the opposite status | {point_but_changed[0]:,} | {_km(point_but_changed[1])} |",
        "",
        "### Where the fused status comes from",
        "",
        "| Source | Ways | Length (km) | ... of which unknown in OSM (km) |",
        "|---|---:|---:|---:|",
    ]
    for source, label in ((fuse.SOURCE_OVERRIDE, "override list"), (fuse.SOURCE_OSM, "explicit OSM tag"),
                          (fuse.SOURCE_NDW_NEWER, "NDW sign newer than the OSM tag"),
                          (fuse.SOURCE_NDW_DIRECT, "NDW sign on the way"),
                          (fuse.SOURCE_NDW_PROPAGATED, "NDW sign propagated from another way"), ("", "none (unknown)")):
        n, m = km_of(lambda w: fused[w.id].source == source)
        _, mu = km_of(lambda w: fused[w.id].source == source and w.osm_status == UNKNOWN)
        lines.append(f"| {label} | {n:,} | {_km(m)} | {_km(mu)} |")

    hops = Counter(min(e.hops for e in fused[w.id].ndw_evidence) for w in ways
                   if fused[w.id].source == fuse.SOURCE_NDW_PROPAGATED)
    lines += [
        "",
        "Propagated ways by distance from the sign (in ways): "
        + ", ".join(f"{h} hop{'s' if h > 1 else ''} {n:,}" for h, n in sorted(hops.items())[:6])
        + (f", more {sum(n for h, n in hops.items() if h > 6):,}" if any(h > 6 for h in hops) else "") + ".",
        "",
        "### Sign attachment",
        "",
        "| Sign | In region | On its matched path | Junction arm | Handed to next path | Ambiguous at cycle junction"
        " | No path fits | Unreadable (no evidence) | Confirmed by sub-sign |",
        "|---|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    hows = Counter((a.code, a.how) for a in fz["attachments"])
    amb = Counter((s.code, fz["ambiguous"][s.id]) for s in signs if s.id in fz["ambiguous"])
    attached_ids = {a.sign_id for a in fz["attachments"]}
    for code in ("G11", "G12a", "G12b", "G13"):
        cs = [s for s in signs if s.code == code]
        unreadable = sum(1 for s in cs if s.id in attached_ids and fuse.sub_sign_effect(code, s.props) == "unreadable")
        confirmed = sum(1 for s in cs if s.id in attached_ids and fuse.sub_sign_effect(code, s.props) == "confirms")
        lines.append(
            f"| {code} | {len(cs):,} | {hows[(code, 'matched')]:,} | {hows[(code, 'junction arm')]:,}"
            f" | {hows[(code, 'handed over')]:,} | {amb[(code, 'cycle junction')]:,}"
            f" | {amb[(code, 'no cycle path match')] + amb[(code, 'no bearing')]:,} | {unreadable:,} | {confirmed:,} |"
        )
    sub_codes = Counter(
        x.get("signCode") for s in signs if s.id in attached_ids for x in s.props.get("supplementarySigns") or []
        if x.get("signCode") in fuse.UNVERIFIED_SUB_SIGN_CODES
    )
    lines += [
        "",
        "OB505 and OB502 (" + ", ".join(f"{c} on {sub_codes[c]:,} attached signs" for c in fuse.UNVERIFIED_SUB_SIGN_CODES)
        + ") are not interpreted. Their meaning was looked up on 2026-11-14 in the OSM wiki list of Dutch"
        " sub-signs (it lists OB51 to OB66 and OB504, 'arrows down-left and down-right', but not OB502 or OB505),"
        " the OSM community forum (OB505 appears under a G12a, undefined) and Noord-Brabant sign drawings"
        " (exb-2019-6446: sizes only). No catalogue entry with their meaning was reachable, so the main sign's"
        " meaning stands. They sit in the arrow sub-sign family next to OB504, which would not change who may"
        " use the path, but that is an inference, not a lookup.",
        "",
        f"## Override list ({len(overrides)} entr{'y' if len(overrides) == 1 else 'ies'})",
        "",
        "`data/overrides.csv` (way id, status, reason, date) is maintained by hand and beats every other source.",
        "",
        "| Way | Override | OSM says | NDW says | Fused | Reason |",
        "|---|---|---|---|---|---|",
    ]
    by_way = {w.id: w for w in ways}
    for way_id, o in sorted(overrides.items()):
        w = by_way.get(way_id)
        if w is None:
            lines.append(f"| {_way_link(way_id)} | {o.status} | not a cycle path in the region | | | {o.reason} |")
            continue
        f = fused[way_id]
        lines.append(f"| {_way_link(way_id)} v{w.version} | {o.status} ({o.date}) | {w.osm_status} ({w.timestamp})"
                     f" | {f.ndw_status or 'no sign'} | **{f.status}** | {o.reason} |")
    lines.append("")
    return lines


def _conflict_summary(ctx: dict) -> list[str]:
    fz_conflicts = ctx["fusion"]["conflicts"]
    pairs = ctx["conflicts"]
    rows = [c for c in fz_conflicts if c["winner"] != "override" or c["ndw_status"] in (ALLOWED, FORBIDDEN)]
    lines = [
        f"After fusion, OSM and NDW disagree on {len(rows):,} ways. Every one is listed with both dates, the winner"
        " and the reason in [`conflicts.md`](conflicts.md).",
        "",
        "| OSM says | NDW says | NDW kind | Ways | NDW newer | Confirmed by sub-sign | Won by NDW | Won by override |",
        "|---|---|---|---:|---:|---:|---:|---:|",
    ]
    groups = Counter((c["osm_status"], c["ndw_status"], c["ndw_kind"]) for c in rows)
    for (osm, ndw, kind), n in sorted(groups.items()):
        g = [c for c in rows if (c["osm_status"], c["ndw_status"], c["ndw_kind"]) == (osm, ndw, kind)]
        lines.append(f"| {osm} | {ndw} | {kind} | {n:,} | {sum(c['ndw_newer'] for c in g):,}"
                     f" | {sum(c['confirmed'] for c in g):,} | {sum(c['winner'] == 'NDW' for c in g):,}"
                     f" | {sum(c['winner'] == 'override' for c in g):,} |")
    signs = ctx["signs"]
    evidence_signs = [x for x in signs if x.code in fuse.EVIDENCE_CODES]
    undated = sum(1 for x in evidence_signs if not fuse.sign_date(x.props))
    rule_rows = [c for c in rows if c["winner"] != "override"]
    outcomes = Counter(c["ndw_rule"] for c in rule_rows)
    km_by = Counter()
    for c in rule_rows:
        km_by[c["ndw_rule"]] += c["length_m"]
    untrusted = Counter(v for v in ctx["fusion"]["untrusted"].values())
    lines += [
        "",
        "### Newer NDW against older OSM: what the rule did",
        "",
        f"NDW sign dates: {sum(1 for x in evidence_signs if x.props.get('validatedOn')):,} of"
        f" {len(evidence_signs):,} G11/G12a/G13 records have `validatedOn`,"
        f" {sum(1 for x in evidence_signs if x.props.get('placedOn')):,} have `placedOn`, and {undated:,} have none of"
        " these three dates. Undated records never win on recency.",
        "",
        "| Outcome (conflicts not settled by an override) | Ways | Length (km) |",
        "|---|---:|---:|",
    ]
    for rule in ("NDW wins", "NDW is newer but its sign attachment is ambiguous", "OSM edit is newer than the NDW sign",
                 "NDW status is propagated from another path",
                 "NDW record has no placed, validated or registered date"):
        label = "Resolved in NDW's favour" if rule == "NDW wins" else f"Left in the conflict report: {rule}"
        lines.append(f"| {label} | {outcomes[rule]:,} | {_km(km_by[rule])} |")
    lines += [
        "",
        "Why attached signs are not unambiguous (all attached signs, not only conflicts): "
        + ", ".join(f"{k} {v:,}" for k, v in untrusted.most_common()) + ".",
        "",
        f"For comparison, the slice 1 point matching found {len(pairs):,} sign-way conflict pairs on"
        f" {len({c['way_id'] for c in pairs}):,} ways. Fusion has fewer because signs at cycle path junctions are"
        " re-attached by direction or dropped as ambiguous.",
    ]
    return lines


def write_conflicts(ctx: dict, out: Path) -> None:
    conflicts = ctx["fusion"]["conflicts"]
    lines = [
        "# Conflicts between OSM, NDW and the override list",
        "",
        f"Generated {time.strftime('%Y-%m-%d %H:%M %Z')} by `cd data && uv run audit`. Do not edit by hand.",
        "",
        "One row per cycle path where the explicit OSM tag and the NDW verdict (direct sign, or propagated from"
        " another path) disagree, plus every path where an override contradicts OSM or NDW. Precedence: override"
        " list > NDW sign newer than the OSM edit and attached unambiguously > explicit OSM tag > NDW > unknown"
        " (see the method in `coverage.md`). *NDW newer* means the newest NDW sign date is more recent than the OSM"
        " way's last edit; rows where OSM still wins are override candidates, and the reason says why NDW did not"
        " win. *Confirmed* means a supplementary sign repeats the moped ban (G11/G13 only). Hops is the number of"
        " paths between the sign's path and this one (0 = the sign stands on this path). The NDW date is the newest"
        " of `validatedOn`, `placedOn` and `registeredOn` (not `lastModifiedOn`); the OSM date is the way's own"
        " timestamp.",
        "",
        f"{len(conflicts):,} rows; {sum(c['ndw_newer'] for c in conflicts):,} with NDW newer;"
        f" {sum(c['winner'] == 'NDW' for c in conflicts):,} won by NDW,"
        f" {sum(c['winner'] == 'OSM' for c in conflicts):,} by OSM,"
        f" {sum(c['winner'] == 'override' for c in conflicts):,} by the override list.",
        "",
        "| Way | Length (m) | OSM status | OSM basis | OSM date | NDW status | NDW kind | Hops | NDW sign(s) | NDW date"
        " | NDW newer | Confirmed | Winner | Fused | Reason |",
        "|---|---:|---|---|---|---|---|---:|---|---|---|---|---|---|---|",
    ]
    for c in conflicts:
        ids = c["sign_ids"]
        shown = ", ".join(f"`{i}`" for i in ids[:2]) + (f" +{len(ids) - 2}" if len(ids) > 2 else "")
        lines.append(
            f"| {_way_link(c['way_id'])} v{c['way_version']} | {round(c['length_m'])} | {c['osm_status']}"
            f" | {c['osm_reason']} | {c['osm_date']} | {c['ndw_status']} | {c['ndw_kind'] or ''} | {c['hops']}"
            f" | {shown} | {c['ndw_date']} | {'yes' if c['ndw_newer'] else 'no'} | {'yes' if c['confirmed'] else 'no'}"
            f" | {c['winner']} | {c['final_status']} | {c['reason']} |"
        )
    out.write_text("\n".join(lines) + "\n")


def _leaflet_assets() -> tuple[str, str]:
    vendor = paths.BUILD_DIR / "vendor"
    vendor.mkdir(parents=True, exist_ok=True)
    out = []
    for name in ("leaflet.min.js", "leaflet.min.css"):
        target = vendor / f"{LEAFLET_VERSION}-{name}"
        if not target.exists():
            r = requests.get(f"{LEAFLET_BASE}/{name}", timeout=60)
            r.raise_for_status()
            target.write_text(r.text)
        out.append(target.read_text())
    return out[0], out[1]


LAYERS = ("conflict", "override", "unknown", "unknown_mixed", "ndw_allowed", "ndw_forbidden", "prop_allowed",
          "prop_forbidden")


def _delta(coords: list[tuple[float, float]]) -> list[int]:
    out, plat, plon = [], 0, 0
    for lat, lon in coords:
        ilat, ilon = round(lat * 1e5), round(lon * 1e5)
        out += [ilat - plat, ilon - plon]
        plat, plon = ilat, ilon
    return out


def _map_layer(w, f, conflict_ways: set[int]) -> str | None:
    if w.id in conflict_ways:
        return "conflict"
    if f.source == fuse.SOURCE_OVERRIDE:
        return "override"
    if f.status == UNKNOWN:
        return "unknown_mixed" if f.ndw_status == "mixed" else "unknown"
    if f.source == fuse.SOURCE_NDW_DIRECT:
        return f"ndw_{f.status}"
    if f.source == fuse.SOURCE_NDW_PROPAGATED:
        return f"prop_{f.status}"
    return None


def _map_data(ctx: dict) -> dict:
    """Compact arrays instead of GeoJSON: coordinates are 1e-5 degree integers, delta encoded."""
    fz = ctx["fusion"]
    fused = fz["fused"]
    conflict_ways = {c["way_id"] for c in fz["conflicts"] if c["winner"] != "override"}
    attached_to = {a.sign_id: a.way_id for a in fz["attachments"]}
    by_id = {s.id: s for s in ctx["signs"]}
    ways = []
    sign_index: dict[str, int] = {}
    signs = []

    def add_sign(s) -> int:
        if s.id not in sign_index:
            sign_index[s.id] = len(signs)
            signs.append([s.id, s.code, s.bearing, s.last_modified, round(s.lat, 6), round(s.lon, 6),
                          attached_to.get(s.id), fz["ambiguous"].get(s.id)])
        return sign_index[s.id]

    for w in ctx["cycleways"].values():
        f = fused[w.id]
        layer = _map_layer(w, f, conflict_ways)
        if layer is None:
            continue
        ways.append([LAYERS.index(layer), w.id, w.version, w.timestamp, w.osm_status, f.ndw_status, round(w.length_m),
                     w.tags, [add_sign(by_id[e.sign_id]) for e in f.ndw_evidence], _delta(w.coords), f.status,
                     f.source, f.source_id, f.ndw_kind,
                     min((e.hops for e in f.ndw_evidence), default=0)])
    for s in ctx["signs"]:
        if (s.code == "G12b" and s.id in attached_to) or fz["ambiguous"].get(s.id) == "cycle junction":
            add_sign(s)
    return {"layers": LAYERS, "ways": ways, "signs": signs}


MAP_TEMPLATE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Cycle path audit map</title>
<style>__LEAFLET_CSS__</style>
<style>
  html, body, #map { height: 100%; margin: 0; }
  body { font: 13px/1.4 -apple-system, system-ui, sans-serif; }
  .legend { background: #fff; padding: 8px 10px; border-radius: 6px; box-shadow: 0 1px 4px rgba(0,0,0,.3); }
  .legend i { display: inline-block; width: 18px; height: 4px; margin-right: 6px; vertical-align: middle; }
  .popup table { border-collapse: collapse; }
  .popup td { padding: 1px 6px 1px 0; vertical-align: top; }
  .popup td:first-child { color: #555; }
  .popup h4 { margin: 0 0 4px; }
</style>
</head>
<body>
<div id="map"></div>
<script>__LEAFLET_JS__</script>
<script>
const DATA = __DATA__;
const META = __META__;
const STYLE = {
  conflict:       { color: "#d1006f", weight: 4, label: "Conflict: OSM and NDW disagree" },
  override:       { color: "#000000", weight: 5, label: "Override list" },
  unknown:        { color: "#f28c00", weight: 3, label: "Unknown after fusion" },
  unknown_mixed:  { color: "#8a5a00", weight: 4, label: "Unknown: NDW signs disagree" },
  ndw_allowed:    { color: "#1a9850", weight: 3, dashArray: "6 4", label: "Unknown in OSM, G12a on the path: allowed" },
  ndw_forbidden:  { color: "#3b4cc0", weight: 3, dashArray: "6 4", label: "Unknown in OSM, G11/G13 on the path: forbidden" },
  prop_allowed:   { color: "#66bd63", weight: 3, dashArray: "2 4", label: "Unknown in OSM, propagated G12a: allowed" },
  prop_forbidden: { color: "#7b8cde", weight: 3, dashArray: "2 4", label: "Unknown in OSM, propagated G11/G13: forbidden" },
};
const SIGN_COLOR = { G11: "#3b4cc0", G13: "#3b4cc0", G12a: "#1a9850", G12b: "#777" };

const map = L.map("map", { preferCanvas: true }).setView(META.center, 9);
L.tileLayer("https://service.pdok.nl/brt/achtergrondkaart/wmts/v2_0/grijs/EPSG:3857/{z}/{x}/{y}.png", {
  minZoom: 6, maxZoom: 19,
  attribution: 'Basemap &copy; <a href="https://www.pdok.nl/">PDOK</a> BRT Achtergrondkaart (CC BY 4.0); paths &copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors; signs: NDW (CC0)'
}).addTo(map);
const region = L.circle(META.center, { radius: META.radius_m, color: "#444", weight: 1, fill: false, interactive: false }).addTo(map);
map.fitBounds(region.getBounds());

function el(tag, text, parent) {
  const e = document.createElement(tag);
  if (text !== undefined) e.textContent = text;
  if (parent) parent.appendChild(e);
  return e;
}
function row(table, k, v) {
  const tr = el("tr", undefined, table);
  el("td", k, tr); el("td", v, tr);
}
function decodeLine(d) {
  const pts = [];
  let lat = 0, lon = 0;
  for (let i = 0; i < d.length; i += 2) {
    lat += d[i]; lon += d[i + 1];
    pts.push([lat / 1e5, lon / 1e5]);
  }
  return pts;
}
function wayPopup(w) {
  const [layer, id, v, ts, osm, ndw, len, tags, signIdx, , status, source, sourceId, kind, hops] = w;
  const box = el("div"); box.className = "popup";
  const h = el("h4", undefined, box);
  const a = el("a", "way " + id, h);
  a.href = "https://www.openstreetmap.org/way/" + id; a.target = "_blank"; a.rel = "noopener";
  const t = el("table", undefined, box);
  row(t, "map layer", STYLE[DATA.layers[layer]].label);
  row(t, "fused status", status + (source ? " (" + source + " " + sourceId + ")" : ""));
  row(t, "OSM status", osm);
  row(t, "NDW verdict", ndw ? ndw + " (" + kind + (kind === "propagated" ? ", " + hops + " hop" + (hops > 1 ? "s" : "") : "") + ")" : "no sign");
  row(t, "version / modified", "v" + v + " / " + ts);
  row(t, "length", len + " m");
  if (signIdx.length) row(t, "NDW signs", signIdx.map(i => DATA.signs[i][1] + " " + DATA.signs[i][0]).join(", "));
  el("h4", "tags", box);
  const tt = el("table", undefined, box);
  Object.keys(tags).sort().forEach(k => row(tt, k, tags[k]));
  return box;
}
function signPopup(s) {
  const [id, code, bearing, modified, , , way, ambiguous] = s;
  const box = el("div"); box.className = "popup";
  el("h4", "NDW " + code, box);
  const t = el("table", undefined, box);
  row(t, "id", id);
  row(t, "bearing", String(bearing));
  row(t, "last modified", modified);
  row(t, "attached to way", way ? String(way) : "none (" + (ambiguous || "not attached") + ")");
  return box;
}

const overlays = {};
DATA.layers.forEach((layer, li) => {
  const g = L.featureGroup();
  let n = 0;
  DATA.ways.forEach(w => {
    if (w[0] !== li) return;
    L.polyline(decodeLine(w[9]), STYLE[layer]).bindPopup(() => wayPopup(w), { maxWidth: 360 }).addTo(g);
    n++;
  });
  g.addTo(map);
  overlays[STYLE[layer].label + " (" + n + ")"] = g;
});
const signs = L.featureGroup(DATA.signs.map(s =>
  L.circleMarker([s[4], s[5]], { radius: 4, color: "#000", weight: 1, fillColor: SIGN_COLOR[s[1]], fillOpacity: 0.9 })
    .bindPopup(() => signPopup(s))
));
overlays["NDW signs on shown ways, attached G12b, ambiguous at junctions (" + DATA.signs.length + ")"] = signs;
map.on("zoomend", () => { if (map.getZoom() >= 14) signs.addTo(map); else signs.remove(); });
L.control.layers(null, overlays, { collapsed: false }).addTo(map);

const legend = L.control({ position: "bottomleft" });
legend.onAdd = () => {
  const d = L.DomUtil.create("div", "legend");
  el("strong", "Cycle paths, " + META.generated, d);
  Object.values(STYLE).forEach(s => {
    const r = el("div", undefined, d);
    const i = el("i", undefined, r); i.style.background = s.color;
    r.appendChild(document.createTextNode(s.label));
  });
  el("div", "NDW signs appear from zoom 14.", d);
  return d;
};
legend.addTo(map);
</script>
</body>
</html>
"""


def write_map(ctx: dict, out: Path) -> None:
    js, css = _leaflet_assets()
    meta = {
        "center": list(ctx["params"]["center"]),
        "radius_m": ctx["params"]["radius_km"] * 1000,
        "generated": time.strftime("%Y-%m-%d"),
    }
    data = json.dumps(_map_data(ctx), separators=(",", ":"), ensure_ascii=False).replace("</", "<\\/")
    html = (
        MAP_TEMPLATE.replace("__LEAFLET_CSS__", css)
        .replace("__LEAFLET_JS__", js)
        .replace("__META__", json.dumps(meta))
        .replace("__DATA__", data)
    )
    out.write_text(html)


def write_sample(sample: list[dict], out: Path) -> None:
    rows = []
    for item in sample:
        w = item["way"]
        rows.append(
            {
                "kind": item["kind"],
                "way_id": w.id,
                "way_version": w.version,
                "way_timestamp": w.timestamp,
                "osm_status": w.osm_status,
                "osm_reason": w.osm_reason,
                "final_status": w.final_status,
                "tags": w.tags,
                "signs": [
                    {"id": s.id, "code": s.code, "status": SIGN_STATUS.get(s.code), "last_modified": s.last_modified,
                     "distance_m": round(s.best_cycleway[0], 1) if s.best_cycleway else None}
                    for s in item["signs"]
                ],
            }
        )
    out.write_text(json.dumps(rows, indent=2, ensure_ascii=False) + "\n")
