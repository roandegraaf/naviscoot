import json
from pathlib import Path

from . import geo

REGION_MARGIN_M = 100


def filter_region(sources: list[Path], dst: Path) -> int:
    features = []
    removed = 0
    for src in sources:
        for f in json.loads(src.read_text())["features"]:
            props = f["properties"]
            if props.get("removedOn"):
                removed += 1
                continue
            lon, lat = f["geometry"]["coordinates"][:2]
            if geo.in_region(lat, lon, margin_m=REGION_MARGIN_M):
                features.append(f)
    dst.write_text(json.dumps({"type": "FeatureCollection", "features": features}) + "\n")
    print(f"NDW: {len(features)} signs in the region written to {dst.name} ({removed} removed signs dropped)")
    return len(features)


def load_region(path: Path) -> list[dict]:
    return json.loads(path.read_text())["features"]
