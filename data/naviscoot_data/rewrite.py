import argparse
import collections
import csv
import re
import sys
import time
from array import array
from pathlib import Path

import osmium

from . import paths
from .classify import ALLOWED, FORBIDDEN, UNKNOWN
from .fuse import Override, load_overrides

MOPED_VALUE = {ALLOWED: "designated", FORBIDDEN: "no", UNKNOWN: "unverified"}
REOPENING_KEYS = ("moped:forward", "moped:backward", "oneway:moped")
OVERRIDE_TAG = "naviscoot:override"
PATH_HIGHWAYS = {"cycleway", "path"}
ROUTABLE_HIGHWAYS = {
    "motorway", "motorway_link", "trunk", "trunk_link", "primary", "primary_link", "secondary", "secondary_link",
    "tertiary", "tertiary_link", "unclassified", "residential", "residential_link", "living_street", "service", "road",
    "track", "footway", "pedestrian", "steps", "bridleway", "cycleway", "path", "bus_guideway", "busway", "corridor",
    "elevator", "platform", "via_ferrata",
}
ROAD_HIGHWAYS = {
    "motorway", "motorway_link", "trunk", "trunk_link", "primary", "primary_link", "secondary",
    "secondary_link", "tertiary", "tertiary_link", "unclassified", "residential", "living_street", "road",
}
URBAN, RURAL = "urban", "rural"
ZONE_KEYS = ("zone:traffic", "zone:maxspeed", "maxspeed:type", "source:maxspeed")
_SPEED_RE = re.compile(r"^\s*(\d+)\s*$")


def load_fused(path: Path = paths.FUSED_ACCESS_CSV) -> dict[int, str]:
    with open(path, newline="") as f:
        return {int(row["way_id"]): row["status"] for row in csv.DictReader(f)}


def zone_from_tags(tags: dict[str, str]) -> str | None:
    for key in ZONE_KEYS:
        value = tags.get(key, "")
        if "NL:urban" in value:
            return URBAN
        if "NL:rural" in value or "NL:motorway" in value:
            return RURAL
    return None


def road_zone(tags: dict[str, str]) -> str | None:
    """Built-up area proxy for a road: inside the bebouwde kom the limit is 50 or lower, outside 60 or higher."""
    highway = tags.get("highway")
    if highway not in ROAD_HIGHWAYS:
        return None
    zone = zone_from_tags(tags)
    if zone:
        return zone
    m = _SPEED_RE.match(tags.get("maxspeed", ""))
    if m:
        return URBAN if int(m.group(1)) <= 50 else RURAL
    if highway in ("residential", "living_street"):
        return URBAN
    return None


def builtup_value(tags: dict[str, str], urban_contacts: int, rural_contacts: int) -> str | None:
    zone = zone_from_tags(tags)
    if zone:
        return "yes" if zone == URBAN else "no"
    if rural_contacts > urban_contacts:
        return "no"
    if urban_contacts:
        return "yes"
    return None


def rewrite_tags(
    tags: dict[str, str], status: str | None, builtup: str | None, override: Override | None = None
) -> dict[str, str]:
    out = dict(tags)
    if override is not None:
        status = override.status
        out[OVERRIDE_TAG] = override.status
    if status is not None:
        out["moped"] = MOPED_VALUE[status]
        if status == FORBIDDEN:
            for key in REOPENING_KEYS:
                out.pop(key, None)
    if builtup is not None:
        out["naviscoot:builtup"] = builtup
    return out


class OverrideError(Exception):
    pass


def unapplied_problems(overrides: dict[int, Override], applied: set[int], highways: dict[int, str | None],
                       source: Path) -> list[str]:
    problems = []
    for way_id in sorted(set(overrides) - applied):
        where = f"way {way_id} ({paths.OVERRIDES_CSV.name}:{overrides[way_id].line})"
        if way_id not in highways:
            problems.append(f"{where} is not in {source.name}")
        elif highways[way_id] is None:
            problems.append(f"{where} has no highway tag, so it is not routable")
        else:
            problems.append(f"{where} is highway={highways[way_id]}, not a routable highway")
    return problems


def spread_builtup(
    labels: dict[int, str | None], path_nodes: dict[int, array], rounds: int = 8
) -> dict[int, str | None]:
    """Paths without road contact inherit the majority label of paths ending on one of their nodes."""
    ending_at: dict[int, list[int]] = collections.defaultdict(list)
    for way_id, refs in path_nodes.items():
        ending_at[refs[0]].append(way_id)
        ending_at[refs[-1]].append(way_id)
    labels = dict(labels)
    for _ in range(rounds):
        updates = {}
        for way_id, label in labels.items():
            if label is not None:
                continue
            votes = collections.Counter(
                labels[other] for ref in path_nodes[way_id] for other in ending_at.get(ref, ())
                if other != way_id and labels[other] is not None
            )
            if votes:
                updates[way_id] = "no" if votes["no"] > votes["yes"] else "yes"
        if not updates:
            break
        labels.update(updates)
    return labels


def _builtup_labels(source: Path) -> dict[int, str | None]:
    urban, rural = osmium.index.IdSet(), osmium.index.IdSet()
    path_tags: dict[int, dict[str, str]] = {}
    path_nodes: dict[int, array] = {}
    fp = osmium.FileProcessor(str(source), osmium.osm.WAY).with_filter(osmium.filter.KeyFilter("highway"))
    for way in fp:
        if len(way.nodes) < 2:
            continue
        if way.tags.get("highway") in PATH_HIGHWAYS:
            path_nodes[way.id] = array("q", (n.ref for n in way.nodes))
            path_tags[way.id] = {k: way.tags[k] for k in ZONE_KEYS if k in way.tags}
            continue
        zone = road_zone(dict(way.tags))
        if zone is not None:
            target = urban if zone == URBAN else rural
            for node in way.nodes:
                target.set(node.ref)
    labels = {
        way_id: builtup_value(path_tags[way_id], sum(r in urban for r in refs), sum(r in rural for r in refs))
        for way_id, refs in path_nodes.items()
    }
    return spread_builtup(labels, path_nodes)


def rewrite(
    source: Path, target: Path, fused: dict[int, str], overrides: dict[int, Override] | None = None
) -> collections.Counter:
    """Raises OverrideError, without writing target, when an override names no routable highway way in source."""
    overrides = overrides or {}
    builtup = _builtup_labels(source)
    stats: collections.Counter = collections.Counter()
    applied: set[int] = set()
    override_highways: dict[int, str | None] = {}
    tmp = target.with_name("partial-" + target.name)
    with osmium.SimpleWriter(str(tmp), overwrite=True) as writer:
        for obj in osmium.FileProcessor(str(source)):
            if not obj.is_way():
                writer.add(obj)
                continue
            highway = obj.tags.get("highway")
            status = fused.get(obj.id) if highway == "cycleway" else None
            override = overrides.get(obj.id)
            if override is not None:
                override_highways[obj.id] = highway
                if highway in ROUTABLE_HIGHWAYS:
                    applied.add(obj.id)
                    stats[f"override {override.status}"] += 1
                else:
                    override = None
            label = builtup.get(obj.id) if highway in PATH_HIGHWAYS else None
            if highway in PATH_HIGHWAYS:
                stats[f"builtup {label or 'unset'}"] += 1
            if status is None and label is None and override is None:
                writer.add(obj)
                continue
            if status is not None:
                stats[f"class {status}"] += 1
            writer.add(obj.replace(tags=rewrite_tags(dict(obj.tags), status, label, override)))
    problems = unapplied_problems(overrides, applied, override_highways, source)
    if problems:
        tmp.unlink()
        raise OverrideError("\n".join(problems))
    tmp.rename(target)
    return stats


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Write the fused bromfiets access into a routable OSM extract.")
    parser.add_argument("--source", type=Path, default=paths.OSM_COUNTRY_PBF)
    parser.add_argument("--target", type=Path, default=paths.ROUTABLE_PBF)
    parser.add_argument("--overrides", type=Path, default=paths.OVERRIDES_CSV)
    args = parser.parse_args(argv)

    started = time.monotonic()
    fused = load_fused()
    overrides = load_overrides(args.overrides)
    try:
        stats = rewrite(args.source, args.target, fused, overrides)
    except OverrideError as e:
        for line in str(e).splitlines():
            print(f"error: override cannot be applied: {line}", file=sys.stderr)
        return 1
    rewritten = sum(n for k, n in stats.items() if k.startswith("class "))
    for key in sorted(stats):
        print(f"{key}: {stats[key]:,}")
    print(f"wrote {args.target} in {time.monotonic() - started:.0f} s")
    if rewritten != len(fused):
        print(f"error: {len(fused):,} ways in {paths.FUSED_ACCESS_CSV.name}, {rewritten:,} rewritten", file=sys.stderr)
        return 1
    return 0
