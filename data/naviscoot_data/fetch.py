import argparse
import json
import sys
import time
from pathlib import Path

import requests

from . import paths
from .clip import clip_region
from .ndw import filter_region

GEOFABRIK_URL = "https://download.geofabrik.de/europe/netherlands-latest.osm.pbf"
NDW_API_URL = "https://data.ndw.nu/api/rest/static-road-data/traffic-signs/v5/current-state"
NDW_CODES = ("G11", "G12a", "G12b", "G13")
NDW_MAX_BYTES = 200_000_000
NDW_MAX_AGE_S = 20 * 3600
USER_AGENT = "naviscoot-data/0.1 (personal research pipeline)"


def _meta_path(target: Path) -> Path:
    return target.with_name(target.name + ".meta.json")


def _read_meta(target: Path) -> dict:
    meta = _meta_path(target)
    if target.exists() and meta.exists():
        return json.loads(meta.read_text())
    return {}


def _write_meta(target: Path, data: dict) -> None:
    _meta_path(target).write_text(json.dumps(data, indent=2) + "\n")


def _stream_to(response: requests.Response, target: Path, max_bytes: int | None = None) -> int:
    part = target.with_name(target.name + ".part")
    written = 0
    last_report = time.monotonic()
    total = int(response.headers.get("Content-Length") or 0)
    with part.open("wb") as fh:
        for chunk in response.iter_content(chunk_size=1 << 20):
            fh.write(chunk)
            written += len(chunk)
            if max_bytes is not None and written > max_bytes:
                part.unlink()
                raise RuntimeError(
                    f"{target.name}: response exceeded {max_bytes} bytes; the API probably ignored the filter"
                )
            if time.monotonic() - last_report > 15:
                pct = f" ({100 * written / total:.0f}%)" if total else ""
                print(f"  {target.name}: {written / 1e6:.0f} MB{pct}", flush=True)
                last_report = time.monotonic()
    part.replace(target)
    return written


def fetch_geofabrik(force: bool) -> bool:
    target = paths.OSM_COUNTRY_PBF
    meta = _read_meta(target)
    headers = {"User-Agent": USER_AGENT}
    if meta and not force:
        if meta.get("etag"):
            headers["If-None-Match"] = meta["etag"]
        if meta.get("last_modified"):
            headers["If-Modified-Since"] = meta["last_modified"]
    with requests.get(GEOFABRIK_URL, headers=headers, stream=True, timeout=60) as r:
        if r.status_code == 304:
            print(f"OSM: {target.name} unchanged (Last-Modified {meta.get('last_modified')}), skipped")
            return False
        r.raise_for_status()
        print(f"OSM: downloading {r.url} ...", flush=True)
        size = _stream_to(r, target)
        _write_meta(
            target,
            {
                "url": r.url,
                "etag": r.headers.get("ETag"),
                "last_modified": r.headers.get("Last-Modified"),
                "bytes": size,
                "downloaded_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            },
        )
        print(f"OSM: {size / 1e6:.0f} MB from {r.url}")
        return True


def _validate_ndw(target: Path, code: str) -> int:
    data = json.loads(target.read_text())
    features = data.get("features")
    if not isinstance(features, list) or not features:
        raise RuntimeError(f"NDW {code}: no features in response")
    wrong = {f["properties"].get("rvvCode") for f in features} - {code}
    if wrong:
        raise RuntimeError(f"NDW {code}: response contains other sign codes {sorted(wrong)[:5]}")
    return len(features)


def fetch_ndw(force: bool) -> bool:
    paths.NDW_RAW_DIR.mkdir(parents=True, exist_ok=True)
    changed = False
    for code in NDW_CODES:
        target = paths.NDW_RAW_DIR / f"{code}.geojson"
        meta = _read_meta(target)
        age = time.time() - meta.get("downloaded_epoch", 0)
        if meta and not force and age < NDW_MAX_AGE_S:
            print(f"NDW: {code} downloaded {age / 3600:.1f} h ago, skipped (NDW sends no ETag; --force to refetch)")
            continue
        with requests.get(
            NDW_API_URL, params={"rvvCode": code}, headers={"User-Agent": USER_AGENT}, stream=True, timeout=120
        ) as r:
            r.raise_for_status()
            size = _stream_to(r, target, max_bytes=NDW_MAX_BYTES)
        count = _validate_ndw(target, code)
        _write_meta(
            target,
            {
                "url": f"{NDW_API_URL}?rvvCode={code}",
                "bytes": size,
                "features": count,
                "downloaded_epoch": int(time.time()),
                "downloaded_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            },
        )
        print(f"NDW: {code} {count} signs nationally ({size / 1e6:.1f} MB)")
        changed = True
    return changed


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Download OSM and NDW sources and clip them to the region.")
    parser.add_argument("--force", action="store_true", help="re-download even if the local copy is current")
    args = parser.parse_args(argv)

    paths.RAW_DIR.mkdir(parents=True, exist_ok=True)
    paths.BUILD_DIR.mkdir(parents=True, exist_ok=True)

    fetch_geofabrik(args.force)
    clip_region(paths.OSM_COUNTRY_PBF, paths.OSM_REGION_PBF)

    fetch_ndw(args.force)
    filter_region([paths.NDW_RAW_DIR / f"{c}.geojson" for c in NDW_CODES], paths.NDW_REGION_GEOJSON)
    return 0


if __name__ == "__main__":
    sys.exit(main())
