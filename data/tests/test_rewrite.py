import re
from array import array

import osmium
import pytest

from naviscoot_data import paths
from naviscoot_data import rewrite as rewrite_module
from naviscoot_data.classify import ALLOWED, FORBIDDEN, UNKNOWN
from naviscoot_data.fuse import Override
from naviscoot_data.rewrite import (
    OVERRIDE_TAG, ROUTABLE_HIGHWAYS, OverrideError, builtup_value, rewrite, rewrite_tags, road_zone, spread_builtup,
)


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


def _override(way_id, status, line=2):
    return Override(way_id=way_id, status=status, reason="test", date="2026-11-14", line=line)


def _tags(path):
    return {w.id: dict(w.tags) for w in osmium.FileProcessor(str(path), osmium.osm.WAY)}


def test_override_applies_to_any_routable_way(tmp_path):
    source, target = tmp_path / "in.osm.pbf", tmp_path / "out.osm.pbf"
    _write(source, [
        (1, [1, 2], {"highway": "residential", "motor_vehicle:forward": "yes", "moped:backward": "yes"}),
        (2, [2, 3], {"highway": "path"}),
        (3, [3, 4], {"highway": "footway"}),
        (4, [4, 5], {"highway": "cycleway", "moped": "designated"}),
        (5, [5, 6], {"highway": "cycleway", "moped": "designated"}),
        (6, [6, 7], {"highway": "secondary", "maxspeed": "50"}),
    ])
    overrides = {
        1: _override(1, FORBIDDEN, 2),
        2: _override(2, FORBIDDEN, 3),
        3: _override(3, ALLOWED, 4),
        4: _override(4, FORBIDDEN, 5),
        5: _override(5, FORBIDDEN, 6),
    }
    stats = rewrite(source, target, {5: FORBIDDEN}, overrides)
    tags = _tags(target)
    assert tags[1]["moped"] == "no" and tags[1][OVERRIDE_TAG] == "forbidden" and "moped:backward" not in tags[1]
    assert tags[2]["moped"] == "no" and tags[2][OVERRIDE_TAG] == "forbidden"
    assert tags[3]["moped"] == "designated" and tags[3][OVERRIDE_TAG] == "allowed"
    assert tags[4]["moped"] == "no" and tags[4][OVERRIDE_TAG] == "forbidden"
    assert tags[5]["moped"] == "no" and tags[5][OVERRIDE_TAG] == "forbidden"
    assert tags[6] == {"highway": "secondary", "maxspeed": "50"}
    assert stats["class forbidden"] == 1
    assert stats["override forbidden"] == 4 and stats["override allowed"] == 1


def test_override_on_a_cycle_path_outside_the_fused_region(tmp_path):
    source, target = tmp_path / "in.osm.pbf", tmp_path / "out.osm.pbf"
    _write(source, [(1, [1, 2], {"highway": "cycleway", "mofa": "yes"})])
    rewrite(source, target, {}, {1: _override(1, FORBIDDEN)})
    assert _tags(target)[1]["moped"] == "no"


def test_rewrite_without_overrides_adds_no_marker(tmp_path):
    source, target = tmp_path / "in.osm.pbf", tmp_path / "out.osm.pbf"
    _write(source, [(1, [1, 2], {"highway": "cycleway"})])
    rewrite(source, target, {1: FORBIDDEN})
    assert OVERRIDE_TAG not in _tags(target)[1]


@pytest.mark.parametrize("ways, expected", [
    ([], "way 99 (overrides.csv:7) is not in in.osm.pbf"),
    ([(99, [1, 2], {"highway": "proposed"})], "way 99 (overrides.csv:7) is highway=proposed, not a routable highway"),
    ([(99, [1, 2], {"building": "yes"})], "way 99 (overrides.csv:7) has no highway tag, so it is not routable"),
])
def test_unapplicable_override_fails_without_writing(tmp_path, ways, expected):
    source, target = tmp_path / "in.osm.pbf", tmp_path / "out.osm.pbf"
    _write(source, [(1, [1, 2], {"highway": "residential"}), *ways])
    with pytest.raises(OverrideError) as e:
        rewrite(source, target, {}, {99: _override(99, FORBIDDEN, 7)})
    assert str(e.value) == expected
    assert not target.exists() and not (tmp_path / "partial-out.osm.pbf").exists()


def test_main_exits_nonzero_naming_the_override(tmp_path, monkeypatch, capsys):
    source, target, csv_path = tmp_path / "in.osm.pbf", tmp_path / "out.osm.pbf", tmp_path / "overrides.csv"
    _write(source, [(1, [1, 2], {"highway": "residential"})])
    csv_path.write_text("way_id,status,reason,date\n1,forbidden,ok,2026-11-14\n424242,forbidden,typo,2026-11-14\n")
    monkeypatch.setattr(rewrite_module, "load_fused", lambda: {})
    code = rewrite_module.main(["--source", str(source), "--target", str(target), "--overrides", str(csv_path)])
    assert code == 1
    assert "way 424242 (overrides.csv:3) is not in in.osm.pbf" in capsys.readouterr().err
    assert not target.exists()


def test_routable_highways_match_the_graph_lua_table():
    lua = (paths.REPO_DIR / "routing" / "valhalla" / "graph.lua").read_text()
    table = lua.split("\nhighway = {\n", 1)[1].split("\n}", 1)[0]
    keys = set(re.findall(r'^\["(\w+)"\]', table, re.M))
    assert ROUTABLE_HIGHWAYS == keys - {"undefined", "unknown"}
