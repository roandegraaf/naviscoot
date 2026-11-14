import argparse
import json
import random
import sys
import time
from collections import defaultdict

import osmium

from . import fuse, geo, paths, report
from .classify import ALLOWED, FORBIDDEN, SIGN_STATUS, UNKNOWN, osm_status, sign_tag_status, tag_sign_disagreement
from .model import CycleWay, Sign
from .ndw import load_region

MATCH_DISTANCE_M = 20.0
MATCH_AXIS_TOLERANCE_DEG = 45.0
GRID_CELL_M = 50.0
STATUS_CODES = ("G11", "G12a", "G13")
SAMPLE_SEED = 20261114
CYCLE_TRACK_VALUES = {"track", "lane", "opposite_track", "opposite_lane"}
SAMPLE_PLAN = {ALLOWED: 4, FORBIDDEN: 3, "conflict": 3}


def _load_signs() -> list[Sign]:
    signs = []
    for f in load_region(paths.NDW_REGION_GEOJSON):
        lon, lat = f["geometry"]["coordinates"][:2]
        p = f["properties"]
        x, y = geo.to_xy(lat, lon)
        signs.append(
            Sign(
                id=f["id"],
                code=p["rvvCode"],
                lat=lat,
                lon=lon,
                x=x,
                y=y,
                bearing=p.get("bearing"),
                last_modified=p.get("lastModifiedOn", ""),
                props=p,
            )
        )
    return [s for s in signs if geo.in_region(s.lat, s.lon)]


def _grid(signs: list[Sign]) -> dict[tuple[int, int], list[Sign]]:
    grid: dict[tuple[int, int], list[Sign]] = defaultdict(list)
    for s in signs:
        grid[(int(s.x // GRID_CELL_M), int(s.y // GRID_CELL_M))].append(s)
    return grid


def _candidate_rank(dist: float, axis: float) -> tuple[bool, bool, float]:
    return axis > fuse.PRECISE_AXIS_TOLERANCE_DEG, axis > MATCH_AXIS_TOLERANCE_DEG, dist


def _match_segments(way_id: int, highway: str, has_track: bool, xy: list[tuple[float, float]], grid) -> set[str]:
    is_cycleway = highway == "cycleway"
    d = MATCH_DISTANCE_M
    nearby: set[str] = set()
    for (ax, ay), (bx, by) in zip(xy, xy[1:]):
        cx0, cx1 = int((min(ax, bx) - d) // GRID_CELL_M), int((max(ax, bx) + d) // GRID_CELL_M)
        cy0, cy1 = int((min(ay, by) - d) // GRID_CELL_M), int((max(ay, by) + d) // GRID_CELL_M)
        seg_bearing = None
        for cx in range(cx0, cx1 + 1):
            for cy in range(cy0, cy1 + 1):
                for s in grid.get((cx, cy), ()):
                    dist = geo.point_segment_distance(s.x, s.y, ax, ay, bx, by)
                    if dist > d:
                        continue
                    if not is_cycleway:
                        if s.best_other is None or dist < s.best_other[0]:
                            s.best_other = (dist, highway, way_id, has_track)
                        continue
                    nearby.add(s.id)
                    if s.best_cycleway_any_bearing is None or dist < s.best_cycleway_any_bearing[0]:
                        s.best_cycleway_any_bearing = (dist, way_id)
                    if seg_bearing is None:
                        seg_bearing = geo.segment_bearing(ax, ay, bx, by)
                    axis = 0.0 if s.bearing is None else geo.axis_difference(seg_bearing, s.bearing)
                    prev = s.candidates.get(way_id)
                    if prev is None or _candidate_rank(dist, axis) < _candidate_rank(*prev):
                        s.candidates[way_id] = (dist, axis)
                    if axis > MATCH_AXIS_TOLERANCE_DEG:
                        continue
                    if s.best_cycleway is None or dist < s.best_cycleway[0]:
                        s.best_cycleway = (dist, way_id)
    return nearby


def _load_ways(grid) -> tuple[dict[int, CycleWay], int, osmium.index.IdSet]:
    cycleways: dict[int, CycleWay] = {}
    road_nodes = osmium.index.IdSet()
    highway_ways = 0
    fp = osmium.FileProcessor(str(paths.OSM_REGION_PBF)).with_locations().with_filter(osmium.filter.KeyFilter("highway"))
    for obj in fp:
        if not obj.is_way():
            continue
        try:
            coords = [(n.lat, n.lon) for n in obj.nodes]
        except osmium.InvalidLocationError:
            continue
        if len(coords) < 2:
            continue
        highway = obj.tags.get("highway")
        highway_ways += 1
        if fuse.is_road({"highway": highway, "service": obj.tags.get("service", "")}):
            for n in obj.nodes:
                road_nodes.set(n.ref)
        xy = [geo.to_xy(lat, lon) for lat, lon in coords]
        has_track = highway != "cycleway" and any(
            t.k.startswith("cycleway") and t.v in CYCLE_TRACK_VALUES for t in obj.tags
        )
        nearby = _match_segments(obj.id, highway, has_track, xy, grid)
        if highway != "cycleway" or not any(geo.in_region(lat, lon) for lat, lon in coords):
            continue
        tags = {t.k: t.v for t in obj.tags}
        status, reason = osm_status(tags)
        cycleways[obj.id] = CycleWay(
            id=obj.id,
            version=obj.version,
            timestamp=obj.timestamp.strftime("%Y-%m-%d"),
            tags=tags,
            coords=coords,
            length_m=sum(geo.haversine_m(*a, *b) for a, b in zip(coords, coords[1:])),
            osm_status=status,
            osm_reason=reason,
            node_ids=[n.ref for n in obj.nodes],
            xy=xy,
            nearby_any=nearby,
        )
    return cycleways, highway_ways, road_nodes


def _apply_ndw(cycleways: dict[int, CycleWay], signs: list[Sign]) -> list[dict]:
    for s in signs:
        if s.code in STATUS_CODES and s.best_cycleway and s.best_cycleway[1] in cycleways:
            cycleways[s.best_cycleway[1]].signs.append(s.id)

    by_id = {s.id: s for s in signs}
    ways_near_sign: dict[str, list[int]] = defaultdict(list)
    for w in cycleways.values():
        for sid in w.nearby_any:
            ways_near_sign[sid].append(w.id)
    conflicts = []
    for w in cycleways.values():
        evidence = {SIGN_STATUS[by_id[sid].code] for sid in w.signs}
        if len(evidence) == 1:
            w.ndw_status = evidence.pop()
        elif len(evidence) > 1:
            w.ndw_status = "mixed"

        if w.osm_status != UNKNOWN:
            w.final_status, w.final_source = w.osm_status, "OSM"
        elif w.ndw_status in (ALLOWED, FORBIDDEN):
            w.final_status, w.final_source = w.ndw_status, "NDW"
        else:
            w.final_status, w.final_source = UNKNOWN, ""

        if w.osm_status == UNKNOWN:
            continue
        for sid in w.signs:
            s = by_id[sid]
            if SIGN_STATUS[s.code] != w.osm_status:
                neighbours = sorted(
                    n for n in ways_near_sign[sid] if n != w.id and cycleways[n].osm_status == SIGN_STATUS[s.code]
                )
                own_sign = sign_tag_status(w.tags)
                if own_sign == SIGN_STATUS[s.code]:
                    explanation = "own traffic_sign agrees with NDW"
                elif neighbours:
                    explanation = "neighbour has sign's status"
                else:
                    explanation = "unexplained"
                conflicts.append(
                    {
                        "way_id": w.id,
                        "way_version": w.version,
                        "osm_status": w.osm_status,
                        "osm_reason": w.osm_reason,
                        "osm_last_modified": w.timestamp,
                        "sign_id": s.id,
                        "sign_code": s.code,
                        "ndw_status": SIGN_STATUS[s.code],
                        "ndw_last_modified": s.last_modified,
                        "distance_m": round(s.best_cycleway[0], 1),
                        "newer_side": "OSM" if w.timestamp > s.last_modified else "NDW",
                        "osm_traffic_sign": w.tags.get("traffic_sign", ""),
                        "neighbours": neighbours,
                        "explanation": explanation,
                    }
                )
    conflicts.sort(key=lambda c: (c["osm_status"], c["way_id"], c["sign_id"]))
    return conflicts


def _sample(cycleways: dict[int, CycleWay], conflicts: list[dict], signs: list[Sign]) -> list[dict]:
    rng = random.Random(SAMPLE_SEED)
    by_id = {s.id: s for s in signs}
    picks = []
    conflict_ways = sorted({c["way_id"] for c in conflicts})
    in_conflict = set(conflict_ways)
    for status in (ALLOWED, FORBIDDEN):
        pool = sorted(
            (w for w in cycleways.values() if w.final_status == status and w.signs and w.id not in in_conflict),
            key=lambda w: w.id,
        )
        for w in rng.sample(pool, min(SAMPLE_PLAN[status], len(pool))):
            picks.append({"kind": status, "way": w, "signs": [by_id[s] for s in w.signs]})
    for way_id in rng.sample(conflict_ways, min(SAMPLE_PLAN["conflict"], len(conflict_ways))):
        w = cycleways[way_id]
        picks.append({"kind": "conflict", "way": w, "signs": [by_id[s] for s in w.signs]})
    return picks


def _source_info() -> dict:
    def meta(p):
        m = p.with_name(p.name + ".meta.json")
        return json.loads(m.read_text()) if m.exists() else {}

    osm = meta(paths.OSM_COUNTRY_PBF)
    ndw = {c: meta(paths.NDW_RAW_DIR / f"{c}.geojson") for c in ("G11", "G12a", "G12b", "G13")}
    return {"osm": osm, "ndw": ndw}


def main(argv: list[str] | None = None) -> int:
    argparse.ArgumentParser(description="Audit bromfiets access coverage of cycle paths in the region.").parse_args(argv)
    for required in (paths.OSM_REGION_PBF, paths.NDW_REGION_GEOJSON):
        if not required.exists():
            print(f"Missing {required}; run `uv run fetch` first.", file=sys.stderr)
            return 1

    t0 = time.monotonic()
    signs = _load_signs()
    grid = _grid(signs)
    print(f"Audit: {len(signs)} NDW signs in the region", flush=True)
    cycleways, highway_ways, road_nodes = _load_ways(grid)
    print(f"Audit: {len(cycleways)} cycle paths, {highway_ways} highway ways scanned ({time.monotonic() - t0:.0f} s)")
    conflicts = _apply_ndw(cycleways, signs)
    sample = _sample(cycleways, conflicts, signs)
    overrides = fuse.load_overrides(paths.OVERRIDES_CSV)
    elsewhere = sorted(set(overrides) - set(cycleways))
    if elsewhere:
        print(f"Audit: {len(elsewhere)} override(s) not on a cycle path in the region"
              f" ({', '.join(map(str, elsewhere))}); the rewrite step applies them and fails if it cannot")
    fusion = fuse.run(cycleways, signs, road_nodes, overrides)
    fuse.write_fused_csv(cycleways, fusion["fused"], paths.FUSED_ACCESS_CSV)
    print(f"Audit: fused {len(fusion['attachments'])} attached signs, wrote {paths.FUSED_ACCESS_CSV}"
          f" ({time.monotonic() - t0:.0f} s)")

    paths.AUDIT_DOCS_DIR.mkdir(parents=True, exist_ok=True)
    context = {
        "cycleways": cycleways,
        "signs": signs,
        "conflicts": conflicts,
        "sample": sample,
        "fusion": fusion,
        "overrides": overrides,
        "sources": _source_info(),
        "disagreements": [w for w in cycleways.values() if tag_sign_disagreement(w.tags)],
        "params": {
            "center": (geo.CENTER_LAT, geo.CENTER_LON),
            "radius_km": geo.RADIUS_M / 1000,
            "match_distance_m": MATCH_DISTANCE_M,
            "axis_tolerance_deg": MATCH_AXIS_TOLERANCE_DEG,
            "sample_seed": SAMPLE_SEED,
        },
    }
    report.write_report(context, paths.AUDIT_DOCS_DIR / "coverage.md", paths.AUDIT_DOCS_DIR / "handcheck.md")
    report.write_conflicts(context, paths.AUDIT_DOCS_DIR / "conflicts.md")
    report.write_map(context, paths.AUDIT_DOCS_DIR / "map.html")
    report.write_sample(sample, paths.BUILD_DIR / "handcheck_sample.json")
    print(f"Audit: wrote docs/audit/coverage.md, conflicts.md and map.html ({time.monotonic() - t0:.0f} s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
