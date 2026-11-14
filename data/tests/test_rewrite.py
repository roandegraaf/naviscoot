from array import array

import osmium

from naviscoot_data.classify import ALLOWED, FORBIDDEN, UNKNOWN
from naviscoot_data.rewrite import builtup_value, rewrite, rewrite_tags, road_zone, spread_builtup


def test_allowed_becomes_designated():
    out = rewrite_tags({"highway": "cycleway", "moped": "yes", "moped:forward": "no"}, ALLOWED, None)
    assert out["moped"] == "designated"
    assert out["moped:forward"] == "no"


def test_forbidden_becomes_no_and_loses_reopening_tags():
    tags = {"highway": "cycleway", "moped": "designated", "moped:backward": "yes", "oneway": "yes", "oneway:moped": "no"}
    out = rewrite_tags(tags, FORBIDDEN, None)
    assert out["moped"] == "no"
    assert "moped:backward" not in out and "oneway:moped" not in out
    assert out["oneway"] == "yes"


def test_unknown_becomes_unverified_marker():
    out = rewrite_tags({"highway": "cycleway"}, UNKNOWN, "no")
    assert out["moped"] == "unverified"
    assert out["naviscoot:builtup"] == "no"


def test_mofa_grants_nothing():
    unknown = rewrite_tags({"highway": "cycleway", "mofa": "yes"}, UNKNOWN, None)
    assert unknown["moped"] == "unverified"
    outside_region = rewrite_tags({"highway": "cycleway", "mofa": "designated"}, None, None)
    assert "moped" not in outside_region


def test_road_zone_from_maxspeed_and_zone_tags():
    assert road_zone({"highway": "secondary", "maxspeed": "50"}) == "urban"
    assert road_zone({"highway": "secondary", "maxspeed": "80"}) == "rural"
    assert road_zone({"highway": "tertiary", "zone:traffic": "NL:rural", "maxspeed": "50"}) == "rural"
    assert road_zone({"highway": "residential"}) == "urban"
    assert road_zone({"highway": "unclassified"}) is None
    assert road_zone({"highway": "cycleway", "maxspeed": "30"}) is None


def test_builtup_value():
    assert builtup_value({}, urban_contacts=2, rural_contacts=1) == "yes"
    assert builtup_value({}, urban_contacts=1, rural_contacts=2) == "no"
    assert builtup_value({}, urban_contacts=1, rural_contacts=1) == "yes"
    assert builtup_value({}, 0, 0) is None
    assert builtup_value({"zone:traffic": "NL:rural"}, urban_contacts=3, rural_contacts=0) == "no"


def test_spread_builtup_follows_connected_paths():
    nodes = {1: array("q", [10, 11, 12]), 2: array("q", [12, 13]), 3: array("q", [13, 14]), 4: array("q", [90, 91])}
    labels = spread_builtup({1: "no", 2: None, 3: None, 4: None}, nodes)
    assert labels == {1: "no", 2: "no", 3: "no", 4: None}


def _write(path, ways):
    with osmium.SimpleWriter(str(path), overwrite=True) as w:
        for i in range(1, 8):
            w.add_node(osmium.osm.mutable.Node(id=i, location=(5.0 + i / 1000, 52.0)))
        for way_id, refs, tags in ways:
            w.add_way(osmium.osm.mutable.Way(id=way_id, nodes=refs, tags=tags))


def test_rewrite_writes_class_and_builtup(tmp_path):
    source, target = tmp_path / "in.osm.pbf", tmp_path / "out.osm.pbf"
    _write(source, [
        (1, [1, 2], {"highway": "primary", "maxspeed": "80"}),
        (2, [2, 3], {"highway": "cycleway", "mofa": "yes"}),
        (3, [3, 4], {"highway": "cycleway", "moped": "designated"}),
        (4, [4, 5], {"highway": "cycleway", "moped": "designated", "oneway:moped": "no"}),
        (5, [6, 7], {"highway": "cycleway", "mofa": "yes"}),
    ])
    stats = rewrite(source, target, {2: UNKNOWN, 3: ALLOWED, 4: FORBIDDEN})
    tags = {w.id: dict(w.tags) for w in osmium.FileProcessor(str(target), osmium.osm.WAY)}
    assert tags[1] == {"highway": "primary", "maxspeed": "80"}
    assert tags[2]["moped"] == "unverified" and tags[2]["naviscoot:builtup"] == "no"
    assert tags[3]["moped"] == "designated" and tags[3]["naviscoot:builtup"] == "no"
    assert tags[4]["moped"] == "no" and "oneway:moped" not in tags[4]
    assert "moped" not in tags[5] and "naviscoot:builtup" not in tags[5]
    assert stats["class unknown"] == stats["class allowed"] == stats["class forbidden"] == 1
    assert len(list(osmium.FileProcessor(str(target), osmium.osm.NODE))) == 7
