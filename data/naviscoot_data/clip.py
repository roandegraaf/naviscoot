import json
import time
from pathlib import Path

import osmium

from . import geo

CLIP_VERSION = 1


def _stamp(src: Path) -> dict:
    st = src.stat()
    return {
        "source": src.name,
        "source_bytes": st.st_size,
        "source_mtime": int(st.st_mtime),
        "center": [geo.CENTER_LAT, geo.CENTER_LON],
        "radius_m": geo.RADIUS_M,
        "clip_version": CLIP_VERSION,
    }


class _NodesInRegion(osmium.SimpleHandler):
    def __init__(self, ids) -> None:
        super().__init__()
        self.ids = ids
        self.min_lat, self.min_lon, self.max_lat, self.max_lon = geo.region_bbox()

    def node(self, n) -> None:
        loc = n.location
        lat, lon = loc.lat, loc.lon
        if self.min_lat <= lat <= self.max_lat and self.min_lon <= lon <= self.max_lon and geo.in_region(lat, lon):
            self.ids.set(n.id)


def clip_region(src: Path, dst: Path) -> bool:
    """Keep every node inside the circle, every way touching it (complete), and relations with a kept member."""
    stamp_path = dst.with_name(dst.name + ".meta.json")
    stamp = _stamp(src)
    if dst.exists() and stamp_path.exists() and json.loads(stamp_path.read_text()) == stamp:
        print(f"Clip: {dst.name} is current, skipped")
        return False

    t0 = time.monotonic()
    tracker = osmium.IdTracker()
    node_ids = tracker.node_ids()
    _NodesInRegion(node_ids).apply_file(str(src))
    print(f"Clip: {len(node_ids)} nodes inside the region ({time.monotonic() - t0:.0f} s)", flush=True)

    way_ids = tracker.way_ids()
    for w in osmium.FileProcessor(str(src), osmium.osm.WAY):
        if any(node_ids.get(r.ref) for r in w.nodes):
            way_ids.set(w.id)
    print(f"Clip: {len(way_ids)} ways touch the region ({time.monotonic() - t0:.0f} s)", flush=True)

    rel_ids = tracker.relation_ids()
    for rel in osmium.FileProcessor(str(src), osmium.osm.RELATION):
        for m in rel.members:
            if (m.type == "w" and way_ids.get(m.ref)) or (m.type == "n" and node_ids.get(m.ref)):
                rel_ids.set(rel.id)
                break
    print(f"Clip: {len(rel_ids)} relations reference the region ({time.monotonic() - t0:.0f} s)", flush=True)

    tracker.complete_backward_references(str(src), relation_depth=0)

    part = dst.with_name(dst.name + ".part.osm.pbf")
    if part.exists():
        part.unlink()
    writer = osmium.WriteHandler(str(part))
    osmium.apply(str(src), tracker.id_filter(), writer)
    writer.close()
    part.replace(dst)
    stamp_path.write_text(json.dumps(stamp, indent=2) + "\n")
    print(f"Clip: wrote {dst.name} ({dst.stat().st_size / 1e6:.0f} MB, {time.monotonic() - t0:.0f} s)")
    return True
