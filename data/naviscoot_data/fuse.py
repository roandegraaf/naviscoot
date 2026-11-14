import csv
import math
import re
from collections import defaultdict
from dataclasses import dataclass, field
from pathlib import Path

from . import geo
from .classify import ALLOWED, FORBIDDEN, SIGN_STATUS, UNKNOWN

EVIDENCE_CODES = ("G11", "G12a", "G13")
END_CODE = "G12b"
MATCH_AXIS_TOLERANCE_DEG = 45.0
PRECISE_AXIS_TOLERANCE_DEG = 20.0
CYCLE_JUNCTION_M = 8.0
ARM_TOLERANCE_DEG = 45.0
ARM_MARGIN_DEG = 15.0
END_HANDOVER_M = 5.0
TRUST_MAX_DISTANCE_M = 10.0
SNAP_TOLERANCE_M = 20.0
SIGN_DATE_FIELDS = ("validatedOn", "placedOn", "registeredOn")
MAX_PROPAGATION_M = 5000.0

ROAD_HIGHWAYS = {
    "motorway", "motorway_link", "trunk", "trunk_link", "primary", "primary_link", "secondary", "secondary_link",
    "tertiary", "tertiary_link", "unclassified", "residential", "living_street", "road", "busway", "service",
}
MINOR_SERVICE = {"driveway", "parking_aisle"}

SOURCE_OVERRIDE = "override"
SOURCE_OSM = "osm"
SOURCE_NDW_DIRECT = "ndw_sign"
SOURCE_NDW_NEWER = "ndw_newer"
SOURCE_NDW_PROPAGATED = "ndw_propagated"

_UNREADABLE_RE = re.compile(r"onleesbaar")
_NO_MOPED_RE = re.compile(r"snor\w*\s+niet|niet\s+brommen|(?:naar|op)\s+de\s+rijbaan")
UNVERIFIED_SUB_SIGN_CODES = ("OB505", "OB502")


def is_road(tags: dict[str, str]) -> bool:
    highway = tags.get("highway")
    if highway not in ROAD_HIGHWAYS:
        return False
    return not (highway == "service" and tags.get("service") in MINOR_SERVICE)


def is_precise(bearing: float | None) -> bool:
    return bearing is not None and bearing % 90 != 0


def sub_sign_texts(props: dict) -> list[str]:
    return [
        re.sub(r"\s+", " ", (x.get("text") or "").strip().lower())
        for x in props.get("supplementarySigns") or []
        if (x.get("text") or "").strip()
    ]


def sub_sign_effect(code: str, props: dict) -> str | None:
    """'unreadable' drops the sign as evidence; 'confirms' marks a G11/G13 whose sub-sign repeats the moped ban.

    Speed-pedelec exemptions are deliberately ignored: they exempt only speed pedelecs, not other mopeds.
    """
    texts = sub_sign_texts(props)
    if any(_UNREADABLE_RE.search(t) for t in texts):
        return "unreadable"
    if SIGN_STATUS.get(code) == FORBIDDEN and any(_NO_MOPED_RE.search(t) for t in texts):
        return "confirms"
    return None


def directed_difference(b1: float, b2: float) -> float:
    return abs((b1 - b2 + 180) % 360 - 180)


@dataclass
class Attachment:
    sign_id: str
    code: str
    way_id: int
    direction: int
    how: str
    start_index: int


@dataclass
class Evidence:
    status: str
    sign_id: str
    sign_date: str
    kind: str
    hops: int
    confirmed: bool
    trusted: bool = False


@dataclass
class Fused:
    status: str
    source: str
    source_id: str
    date: str
    ndw_status: str | None = None
    ndw_kind: str | None = None
    ndw_evidence: list[Evidence] = field(default_factory=list)


class Topology:
    def __init__(self, ways: dict, road_nodes):
        self.ways = ways
        self.road_nodes = road_nodes
        self.incidences: dict[int, list[tuple[int, int]]] = defaultdict(list)
        for w in ways.values():
            for i, n in enumerate(w.node_ids):
                self.incidences[n].append((w.id, i))

    def is_closed(self, way_id: int) -> bool:
        nodes = self.ways[way_id].node_ids
        return nodes[0] == nodes[-1]

    def arms(self, node: int) -> list[tuple[int, int, int]]:
        """Directions in which a cycle path leaves the node, as (way id, node index, +1/-1 along the node order)."""
        out = []
        for way_id, i in self.incidences.get(node, ()):
            last = len(self.ways[way_id].node_ids) - 1
            if i < last:
                out.append((way_id, i, 1))
            if i > 0:
                out.append((way_id, i, -1))
        return out

    def arm_bearing(self, way_id: int, node_index: int, direction: int) -> float:
        xy = self.ways[way_id].xy
        a, b = xy[node_index], xy[node_index + direction]
        return geo.segment_bearing(*a, *b)

    def exit_node(self, way_id: int, direction: int) -> int:
        nodes = self.ways[way_id].node_ids
        return nodes[-1] if direction == 1 else nodes[0]

    def entry_index(self, way_id: int, direction: int) -> int:
        return 0 if direction == 1 else len(self.ways[way_id].node_ids) - 1

    def blocked_inside(self, way_id: int, start_index: int, direction: int) -> bool:
        """A road or another cycle path joins between start_index and the exit node (exclusive)."""
        nodes = self.ways[way_id].node_ids
        exit_index = len(nodes) - 1 if direction == 1 else 0
        for k in range(start_index, exit_index, direction):
            if nodes[k] in self.road_nodes or len(self.arms(nodes[k])) >= 3:
                return True
        return False


def choose_way(sign, known) -> int | None:
    candidates = {w: c for w, c in sign.candidates.items() if w in known}
    if is_precise(sign.bearing):
        tight = [(d, w) for w, (d, ax) in candidates.items() if ax <= PRECISE_AXIS_TOLERANCE_DEG]
        if tight:
            return min(tight)[1]
    fitting = [(d, w) for w, (d, ax) in candidates.items() if ax <= MATCH_AXIS_TOLERANCE_DEG]
    return min(fitting)[1] if fitting else None


def _project(xy: list[tuple[float, float]], px: float, py: float) -> tuple[int, float, float]:
    """Nearest segment index, the distance along the way to the projected point, and that segment's bearing."""
    best = None
    along = 0.0
    for i, ((ax, ay), (bx, by)) in enumerate(zip(xy, xy[1:])):
        dx, dy = bx - ax, by - ay
        seg = math.hypot(dx, dy)
        t = 0.0 if seg == 0 else max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / (seg * seg)))
        dist = math.hypot(px - (ax + t * dx), py - (ay + t * dy))
        if best is None or dist < best[0]:
            best = (dist, i, along + t * seg)
        along += seg
    _, i, s = best
    return i, s, geo.segment_bearing(*xy[i], *xy[i + 1])


def _way_length_xy(xy) -> float:
    return sum(math.hypot(bx - ax, by - ay) for (ax, ay), (bx, by) in zip(xy, xy[1:]))


def attach(sign, topo: Topology) -> Attachment | str:
    """Decide which cycle path a sign governs and in which travel direction, or return why it is ambiguous.

    NDW bearings are the travel direction of the traffic the sign addresses (calibrated on path entrances).
    """
    if sign.bearing is None:
        return "no bearing"
    way_id = choose_way(sign, topo.ways)
    if way_id is None:
        return "no cycle path match"
    way = topo.ways[way_id]

    junctions = []
    for i, n in enumerate(way.node_ids):
        d = math.hypot(way.xy[i][0] - sign.x, way.xy[i][1] - sign.y)
        if d <= CYCLE_JUNCTION_M and len(topo.arms(n)) >= 3:
            junctions.append((d, n))
    if junctions:
        node = min(junctions)[1]
        scored = []
        for arm_way, idx, direction in topo.arms(node):
            diff = directed_difference(topo.arm_bearing(arm_way, idx, direction), sign.bearing)
            scored.append((diff, arm_way, direction))
        scored.sort()
        best = scored[0]
        tolerance = PRECISE_AXIS_TOLERANCE_DEG if is_precise(sign.bearing) else ARM_TOLERANCE_DEG
        clear = len(scored) == 1 or scored[1][0] - best[0] >= ARM_MARGIN_DEG
        if best[0] <= tolerance and clear:
            arm_way, arm_direction = best[1], best[2]
            arm_index = next(i for w, i, d in topo.arms(node) if (w, d) == (arm_way, arm_direction))
            return Attachment(sign.id, sign.code, arm_way, arm_direction, "junction arm", arm_index + arm_direction)
        return "cycle junction"

    segment, along, seg_bearing = _project(way.xy, sign.x, sign.y)
    direction = 1 if math.cos(math.radians(seg_bearing - sign.bearing)) > 0 else -1
    remaining = (_way_length_xy(way.xy) - along) if direction == 1 else along
    if remaining < END_HANDOVER_M and not topo.is_closed(way_id):
        end = topo.exit_node(way_id, direction)
        if end not in topo.road_nodes:
            arms = topo.arms(end)
            others = [(w, d) for w, _, d in arms if w != way_id]
            if len(arms) == 2 and len(others) == 1:
                nxt, nxt_direction = others[0]
                return Attachment(sign.id, sign.code, nxt, nxt_direction, "handed over",
                                  topo.entry_index(nxt, nxt_direction) + nxt_direction)
    return Attachment(sign.id, sign.code, way_id, direction, "matched", segment + 1 if direction == 1 else segment)


def sign_date(props: dict) -> str:
    """When the sign was last seen in the field: validated, placed or first registered.

    `lastModifiedOn` is not used: it moves with NDW's road-network (NWB) re-link batches, not with field visits.
    """
    return max((props[k] for k in SIGN_DATE_FIELDS if props.get(k)), default="")


def trust_problem(sign, att: Attachment, topo: Topology) -> str | None:
    """Why a direct attachment is not unambiguous enough for a newer NDW record to beat OSM, or None."""
    if att.how != "matched":
        return f"sign attached as {att.how}"
    if any(x.get("signCode") in UNVERIFIED_SUB_SIGN_CODES for x in sign.props.get("supplementarySigns") or []):
        return "sign carries a sub-sign of unverified meaning (OB505/OB502)"
    dist = sign.candidates.get(att.way_id, (math.inf, 0.0))[0]
    if dist > TRUST_MAX_DISTANCE_M:
        return f"sign more than {TRUST_MAX_DISTANCE_M:.0f} m from the path"
    competing = [w for w, (d, ax) in sign.candidates.items()
                 if w != att.way_id and w in topo.ways and d <= SNAP_TOLERANCE_M and ax <= MATCH_AXIS_TOLERANCE_DEG]
    if competing:
        return "another fitting cycle path within 20 m"
    way = topo.ways[att.way_id]
    for i, n in enumerate(way.node_ids):
        if len(topo.arms(n)) >= 3 and math.hypot(way.xy[i][0] - sign.x, way.xy[i][1] - sign.y) <= SNAP_TOLERANCE_M:
            return "cycle path junction within 20 m"
    return None


def propagate(attachments: list[Attachment], signs_by_id: dict, topo: Topology,
              untrusted: dict[str, str] | None = None) -> dict[int, list[Evidence]]:
    """Direct evidence on the attached way, then walk forward until a stop condition."""
    signed_ways = {a.way_id for a in attachments}
    ends_on = defaultdict(set)
    for a in attachments:
        if a.code == END_CODE:
            ends_on[a.way_id].add(a.direction)

    evidence: dict[int, list[Evidence]] = defaultdict(list)
    for a in attachments:
        if a.code not in EVIDENCE_CODES:
            continue
        sign = signs_by_id[a.sign_id]
        effect = sub_sign_effect(sign.code, sign.props)
        if effect == "unreadable":
            continue
        status = SIGN_STATUS[a.code]
        confirmed = effect == "confirms"
        date = sign_date(sign.props)
        trusted = untrusted is not None and a.sign_id not in untrusted
        evidence[a.way_id].append(Evidence(status, a.sign_id, date, "direct", 0, confirmed, trusted))

        way_id, direction, hops, scan_from = a.way_id, a.direction, 0, a.start_index
        walked = topo.ways[way_id].length_m
        visited = {way_id}
        while True:
            if topo.is_closed(way_id) or direction in ends_on[way_id]:
                break
            if topo.ways[way_id].osm_status not in (UNKNOWN, status):
                break
            if topo.blocked_inside(way_id, scan_from, direction):
                break
            node = topo.exit_node(way_id, direction)
            if node in topo.road_nodes:
                break
            arms = topo.arms(node)
            if len(arms) != 2:
                break
            nxt = [(w, d) for w, _, d in arms if w != way_id]
            if len(nxt) != 1:
                break
            way_id, direction = nxt[0]
            if way_id in visited or way_id in signed_ways or topo.is_closed(way_id):
                break
            scan_from = topo.entry_index(way_id, direction) + direction
            if topo.blocked_inside(way_id, scan_from, direction):
                break
            walked += topo.ways[way_id].length_m
            if walked > MAX_PROPAGATION_M:
                break
            hops += 1
            visited.add(way_id)
            evidence[way_id].append(Evidence(status, a.sign_id, date, "propagated", hops, confirmed))
    return evidence


def ndw_verdict(items: list[Evidence]) -> tuple[str | None, str | None, list[Evidence]]:
    """Direct evidence beats propagated evidence; disagreement within the stronger kind is 'mixed'."""
    for kind in ("direct", "propagated"):
        chosen = [e for e in items if e.kind == kind]
        if not chosen:
            continue
        statuses = {e.status for e in chosen}
        if len(statuses) > 1:
            return "mixed", kind, chosen
        return statuses.pop(), kind, sorted(chosen, key=lambda e: e.sign_date, reverse=True)
    return None, None, []


@dataclass
class Override:
    way_id: int
    status: str
    reason: str
    date: str
    line: int


def load_overrides(path: Path) -> dict[int, Override]:
    out: dict[int, Override] = {}
    with path.open(newline="") as f:
        for line, row in enumerate(csv.DictReader(f), start=2):
            status = row["status"].strip()
            if status not in (ALLOWED, FORBIDDEN):
                raise ValueError(f"{path.name}:{line}: status must be allowed or forbidden, got {status!r}")
            way_id = int(row["way_id"])
            if way_id in out:
                raise ValueError(f"{path.name}:{line}: way {way_id} is listed twice")
            out[way_id] = Override(way_id, status, row["reason"].strip(), row["date"].strip(), line)
    return out


def ndw_over_osm(way, ndw_status: str | None, ndw_kind: str | None, chosen: list[Evidence]) -> tuple[bool, str]:
    """A newer NDW record beats an older explicit OSM tag only when its sign is dated and attached unambiguously."""
    if way.osm_status == UNKNOWN or ndw_status not in (ALLOWED, FORBIDDEN) or ndw_status == way.osm_status:
        return False, ""
    if ndw_kind != "direct":
        return False, "NDW status is propagated from another path"
    dated = [e for e in chosen if e.sign_date]
    if not dated:
        return False, "NDW record has no placed, validated or registered date"
    newest = max(e.sign_date for e in dated)
    if newest <= way.timestamp:
        return False, "OSM edit is newer than the NDW sign"
    trusted_newer = [e for e in dated if e.trusted and e.sign_date > way.timestamp]
    if not trusted_newer:
        return False, "NDW is newer but its sign attachment is ambiguous"
    return True, "NDW sign is newer than the OSM edit and attached unambiguously"


def fuse_way(way, items: list[Evidence], override: Override | None) -> Fused:
    """Precedence: override > newer, unambiguous NDW sign > OSM explicit tag > NDW (direct, then propagated) > unknown."""
    ndw_status, ndw_kind, chosen = ndw_verdict(items)
    extra = {"ndw_status": ndw_status, "ndw_kind": ndw_kind, "ndw_evidence": chosen}
    if override is not None:
        return Fused(override.status, SOURCE_OVERRIDE, f"overrides.csv:{override.line}", override.date, **extra)
    wins, _ = ndw_over_osm(way, ndw_status, ndw_kind, chosen)
    if wins:
        best = max((e for e in chosen if e.trusted and e.sign_date > way.timestamp), key=lambda e: e.sign_date)
        return Fused(ndw_status, SOURCE_NDW_NEWER, best.sign_id, best.sign_date, **extra)
    if way.osm_status != UNKNOWN:
        return Fused(way.osm_status, SOURCE_OSM, f"way/{way.id}/v{way.version}", way.timestamp, **extra)
    if ndw_status in (ALLOWED, FORBIDDEN):
        source = SOURCE_NDW_DIRECT if ndw_kind == "direct" else SOURCE_NDW_PROPAGATED
        return Fused(ndw_status, source, chosen[0].sign_id, chosen[0].sign_date, **extra)
    return Fused(UNKNOWN, "", "", "", **extra)


def conflict_for(way, fused: Fused, override: Override | None, untrusted: dict[str, str] | None = None) -> dict | None:
    ndw = fused.ndw_status if fused.ndw_status in (ALLOWED, FORBIDDEN) else None
    osm = way.osm_status if way.osm_status != UNKNOWN else None
    disagree = bool(osm and ndw and osm != ndw)
    if not disagree and not (override is not None and (osm or ndw) and override.status != (osm or ndw)):
        return None
    evidence = fused.ndw_evidence if ndw else []
    ndw_date = max((e.sign_date for e in evidence), default="")
    if disagree:
        wins, rule = ndw_over_osm(way, fused.ndw_status, fused.ndw_kind, evidence)
        if rule == "NDW is newer but its sign attachment is ambiguous" and untrusted:
            details = sorted({untrusted[e.sign_id] for e in evidence if e.sign_id in untrusted})
            rule += " (" + "; ".join(details) + ")"
    else:
        wins, rule = False, ""
    if override is not None:
        winner, reason = "override", override.reason
    elif wins:
        winner, reason = "NDW", rule
    else:
        winner = "OSM"
        reason = "explicit OSM tag kept: " + rule
    return {
        "way_id": way.id,
        "way_version": way.version,
        "osm_status": osm or UNKNOWN,
        "osm_reason": way.osm_reason,
        "osm_date": way.timestamp,
        "ndw_status": ndw or (fused.ndw_status or "none"),
        "ndw_kind": fused.ndw_kind,
        "sign_ids": [e.sign_id for e in evidence],
        "ndw_date": ndw_date,
        "hops": min((e.hops for e in evidence), default=0),
        "confirmed": any(e.confirmed for e in evidence),
        "ndw_newer": bool(ndw_date) and ndw_date > way.timestamp,
        "ndw_rule": "NDW wins" if wins else rule.split(" (")[0],
        "winner": winner,
        "final_status": fused.status,
        "reason": reason,
        "length_m": way.length_m,
    }


def bearing_calibration(signs: list, topo: Topology, max_distance_m: float = 10.0) -> dict[str, int]:
    """Compare sign bearings with the direction into the path at path entrances (ends with a single arm)."""
    out = {"aligned": 0, "opposite": 0, "across": 0}
    for s in signs:
        if s.code not in EVIDENCE_CODES or s.bearing is None:
            continue
        way_id = choose_way(s, topo.ways)
        if way_id is None:
            continue
        way = topo.ways[way_id]
        for i in (0, len(way.node_ids) - 1):
            arms = topo.arms(way.node_ids[i])
            if len(arms) != 1 or math.hypot(way.xy[i][0] - s.x, way.xy[i][1] - s.y) > max_distance_m:
                continue
            _, idx, direction = arms[0]
            diff = directed_difference(topo.arm_bearing(way_id, idx, direction), s.bearing)
            out["aligned" if diff < 45 else "opposite" if diff > 135 else "across"] += 1
            break
    return out


def run(ways: dict, signs: list, road_nodes, overrides: dict[int, Override]) -> dict:
    topo = Topology(ways, road_nodes)
    signs_by_id = {s.id: s for s in signs}
    attachments: list[Attachment] = []
    ambiguous: dict[str, str] = {}
    for s in signs:
        if s.code not in EVIDENCE_CODES and s.code != END_CODE:
            continue
        result = attach(s, topo)
        if isinstance(result, Attachment):
            attachments.append(result)
        else:
            ambiguous[s.id] = result
    untrusted = {}
    for a in attachments:
        problem = trust_problem(signs_by_id[a.sign_id], a, topo)
        if problem:
            untrusted[a.sign_id] = problem
    evidence = propagate(attachments, signs_by_id, topo, untrusted)
    fused: dict[int, Fused] = {}
    conflicts = []
    for w in ways.values():
        override = overrides.get(w.id)
        fused[w.id] = fuse_way(w, evidence.get(w.id, []), override)
        c = conflict_for(w, fused[w.id], override, untrusted)
        if c:
            conflicts.append(c)
    order = {"override": 0, "NDW": 1, "OSM": 2}
    conflicts.sort(key=lambda c: (order[c["winner"]], c["osm_status"], c["ndw_kind"] or "", c["way_id"]))
    return {"attachments": attachments, "ambiguous": ambiguous, "untrusted": untrusted, "evidence": evidence,
            "fused": fused,
            "conflicts": conflicts, "calibration": bearing_calibration(signs, topo)}


def write_fused_csv(ways: dict, fused: dict[int, Fused], out: Path) -> None:
    with out.open("w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["way_id", "status", "source", "source_id", "date"])
        for way_id in sorted(ways):
            r = fused[way_id]
            writer.writerow([way_id, r.status, r.source, r.source_id, r.date])
