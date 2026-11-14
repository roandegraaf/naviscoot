import json
import os
from pathlib import Path

import osmium
import pytest

from naviscoot_data import paths
from naviscoot_data.fuse import load_overrides
from naviscoot_data.rewrite import MOPED_VALUE, load_fused
from naviscoot_data.valhalla import Valhalla, verified_only_route

pytestmark = pytest.mark.valhalla

CASES = json.loads(paths.REGRESSION_CASES.read_text())["cases"]
FUSED_CSV = Path(os.environ.get("FUSED_ACCESS_CSV", paths.SERVED_FUSED_CSV))


@pytest.fixture(scope="module")
def valhalla() -> Valhalla:
    client = Valhalla()
    client.status()
    return client


@pytest.fixture(scope="module")
def unverified_ids() -> set[int]:
    return {way_id for way_id, status in load_fused(FUSED_CSV).items() if status == "unknown"}


def _points(case: dict) -> list[tuple[float, float]]:
    return [tuple(p) for p in case["points"]]


@pytest.mark.parametrize("case", CASES, ids=[c["id"] for c in CASES])
def test_case(case: dict, valhalla: Valhalla, unverified_ids: set[int]):
    kind = case["kind"]
    if kind == "match":
        edges = [e for e in valhalla.map_match(_points(case)) if e.way_id == case["way_id"]]
        assert edges, f"way {case['way_id']} not matched"
        assert {e.speed for e in edges} == {case["expect_speed"]}
        assert case["way_id"] in unverified_ids
        return

    if kind == "verified_only":
        route, requests = verified_only_route(valhalla, _points(case), unverified_ids)
        assert not set(route.way_ids[1:-1]) & unverified_ids
        assert set(valhalla.route(_points(case)).way_ids[1:-1]) & unverified_ids, "case no longer crosses an unverified way"
        assert requests <= case["max_requests"]
        return

    route = valhalla.route(_points(case))
    used = set(route.way_ids)
    if avoid := case.get("avoid_way_ids"):
        assert not used & set(avoid), f"route uses forbidden way(s) {sorted(used & set(avoid))}"
    if use := case.get("use_way_ids"):
        assert set(use) <= used, f"route misses way(s) {sorted(set(use) - used)}"
    if "max_length_km" in case:
        assert route.length_km < case["max_length_km"]
    if "min_length_km" in case:
        assert route.length_km >= case["min_length_km"]
    if naive := case.get("naive_costing"):
        naive_route = valhalla.route(_points(case), costing=naive)
        assert set(avoid) <= set(naive_route.way_ids), "the case no longer tempts a naive router; pick another way"


def _moped_tags(pbf, way_ids: set[int]) -> dict[int, str | None]:
    fp = osmium.FileProcessor(str(pbf), osmium.osm.WAY).with_filter(osmium.filter.IdFilter(way_ids))
    return {w.id: w.tags.get("moped") for w in fp}


def test_overrides_are_written_into_the_routable_extract():
    overrides = load_overrides(paths.OVERRIDES_CSV)
    osm = _moped_tags(paths.OSM_REGION_PBF, set(overrides))
    routable = _moped_tags(paths.ROUTABLE_PBF, set(overrides))
    for way_id, override in overrides.items():
        assert routable[way_id] == MOPED_VALUE[override.status], f"override {way_id} not applied"
    assert any(osm.get(w) != routable[w] for w in overrides), "no override changes OSM; the override cases prove nothing"
