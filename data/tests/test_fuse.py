import pytest

from naviscoot_data import fuse
from naviscoot_data.classify import ALLOWED, FORBIDDEN, UNKNOWN
from naviscoot_data.model import CycleWay, Sign


def way(way_id, nodes, points, osm_status=UNKNOWN, timestamp="2020-01-01", version=1):
    length = sum(((bx - ax) ** 2 + (by - ay) ** 2) ** 0.5 for (ax, ay), (bx, by) in zip(points, points[1:]))
    return CycleWay(
        id=way_id, version=version, timestamp=timestamp, tags={}, coords=[], length_m=length,
        osm_status=osm_status, osm_reason="moped tag" if osm_status != UNKNOWN else "no moped information",
        node_ids=nodes, xy=points,
    )


def sign(sign_id, code, x, y, bearing, candidates, date="2022-01-01", texts=(), registered="2016-05-01"):
    props = {"supplementarySigns": [{"signCode": "OTHER", "text": t} for t in texts], "lastModifiedOn": date}
    if registered:
        props["registeredOn"] = registered
    return Sign(id=sign_id, code=code, lat=0, lon=0, x=x, y=y, bearing=bearing, last_modified=date, props=props,
                candidates=candidates)


def chain():
    """Four cycle paths in a straight line heading east: 1-2, 2-3, 3-4, 4-5, each 100 m."""
    return {
        10: way(10, [1, 2], [(0, 0), (100, 0)]),
        20: way(20, [2, 3], [(100, 0), (200, 0)]),
        30: way(30, [3, 4], [(200, 0), (300, 0)]),
        40: way(40, [4, 5], [(300, 0), (400, 0)]),
    }


def statuses(ways, signs, road_nodes=(), overrides=None):
    result = fuse.run(ways, signs, set(road_nodes), overrides or {})
    return {w: f.status for w, f in result["fused"].items()}, result


def test_g11_propagates_until_g12b_and_not_beyond():
    ways = chain()
    signs = [
        sign("start", "G11", 3, 2, 90, {10: (2.0, 0.0)}),
        sign("end", "G12b", 203, 2, 90, {30: (2.0, 0.0)}),
    ]
    got, result = statuses(ways, signs)
    assert got == {10: FORBIDDEN, 20: FORBIDDEN, 30: UNKNOWN, 40: UNKNOWN}
    assert result["fused"][10].source == fuse.SOURCE_NDW_DIRECT
    assert result["fused"][20].source == fuse.SOURCE_NDW_PROPAGATED
    assert result["fused"][20].source_id == "start"


def test_propagation_stops_at_a_road_junction():
    got, _ = statuses(chain(), [sign("start", "G11", 3, 2, 90, {10: (2.0, 0.0)})], road_nodes={3})
    assert got == {10: FORBIDDEN, 20: FORBIDDEN, 30: UNKNOWN, 40: UNKNOWN}


def test_propagation_stops_at_a_branching_junction():
    ways = chain()
    ways[50] = way(50, [3, 6], [(200, 0), (200, 100)])
    got, _ = statuses(ways, [sign("start", "G11", 3, 2, 90, {10: (2.0, 0.0)})])
    assert got == {10: FORBIDDEN, 20: FORBIDDEN, 30: UNKNOWN, 40: UNKNOWN, 50: UNKNOWN}


def chain_with_middle_node():
    ways = chain()
    ways[20] = way(20, [2, 7, 3], [(100, 0), (150, 0), (200, 0)])
    return ways


def test_path_with_a_road_crossing_inside_is_not_entered():
    got, _ = statuses(chain_with_middle_node(), [sign("start", "G11", 3, 2, 90, {10: (2.0, 0.0)})], road_nodes={7})
    assert got == {10: FORBIDDEN, 20: UNKNOWN, 30: UNKNOWN, 40: UNKNOWN}


def test_path_with_a_side_path_joining_inside_is_not_entered():
    ways = chain_with_middle_node()
    ways[50] = way(50, [7, 8], [(150, 0), (150, 100)])
    got, _ = statuses(ways, [sign("start", "G11", 3, 2, 90, {10: (2.0, 0.0)})])
    assert got == {10: FORBIDDEN, 20: UNKNOWN, 30: UNKNOWN, 40: UNKNOWN, 50: UNKNOWN}


def test_road_crossing_ahead_on_the_signed_path_keeps_the_path_but_stops_the_walk():
    ways = chain()
    ways[10] = way(10, [1, 9, 2], [(0, 0), (50, 0), (100, 0)])
    got, _ = statuses(ways, [sign("start", "G11", 3, 2, 90, {10: (2.0, 0.0)})], road_nodes={9})
    assert got == {10: FORBIDDEN, 20: UNKNOWN, 30: UNKNOWN, 40: UNKNOWN}


def test_road_crossing_behind_the_sign_does_not_stop_it():
    ways = chain()
    ways[10] = way(10, [1, 9, 2], [(0, 0), (50, 0), (100, 0)])
    got, _ = statuses(ways, [sign("start", "G11", 60, 2, 90, {10: (2.0, 0.0)})], road_nodes={9})
    assert got == {10: FORBIDDEN, 20: FORBIDDEN, 30: FORBIDDEN, 40: FORBIDDEN}


def test_propagation_stops_after_a_path_osm_tags_with_the_opposite_status():
    ways = chain()
    ways[20].osm_status = FORBIDDEN
    got, result = statuses(ways, [sign("start", "G12a", 3, 2, 90, {10: (2.0, 0.0)})])
    assert got == {10: ALLOWED, 20: FORBIDDEN, 30: UNKNOWN, 40: UNKNOWN}
    assert [c["way_id"] for c in result["conflicts"]] == [20]


def test_propagation_follows_the_sign_direction_only():
    got, _ = statuses(chain(), [sign("west", "G12a", 303, 2, 270, {30: (2.0, 0.0)})])
    assert got == {10: ALLOWED, 20: ALLOWED, 30: ALLOWED, 40: UNKNOWN}


def test_propagation_stops_at_another_g_sign():
    signs = [
        sign("start", "G11", 3, 2, 90, {10: (2.0, 0.0)}),
        sign("other", "G12a", 210, 2, 90, {30: (2.0, 0.0)}),
    ]
    got, _ = statuses(chain(), signs)
    assert got == {10: FORBIDDEN, 20: FORBIDDEN, 30: ALLOWED, 40: ALLOWED}


def test_reverse_g12b_does_not_stop_the_walk():
    signs = [
        sign("start", "G11", 3, 2, 90, {10: (2.0, 0.0)}),
        sign("reverse_end", "G12b", 50, 2, 270, {10: (2.0, 0.0)}),
    ]
    got, _ = statuses(chain(), signs)
    assert got[20] == FORBIDDEN


def test_sign_at_a_cycle_junction_attaches_to_the_arm_in_its_direction():
    ways = {
        10: way(10, [1, 2], [(0, 0), (100, 0)]),
        20: way(20, [2, 3], [(100, 0), (200, 0)]),
        30: way(30, [2, 4], [(100, 0), (100, 100)]),
    }
    s = sign("north", "G11", 102, 2, 0, {10: (2.0, 90.0), 20: (2.0, 90.0), 30: (2.0, 0.0)})
    topo = fuse.Topology(ways, set())
    att = fuse.attach(s, topo)
    assert (att.way_id, att.direction, att.how) == (30, 1, "junction arm")


def test_sign_at_a_cycle_junction_without_a_clear_arm_is_ambiguous():
    ways = {
        10: way(10, [1, 2], [(0, 0), (100, 0)]),
        20: way(20, [2, 3], [(100, 0), (171, 71)]),
        30: way(30, [2, 4], [(100, 0), (171, -71)]),
    }
    s = sign("east", "G11", 102, 1, 90, {20: (2.0, 45.0), 30: (2.0, 45.0)})
    assert fuse.attach(s, fuse.Topology(ways, set())) == "cycle junction"


def test_sign_at_the_far_end_is_handed_to_the_next_path():
    s = sign("late", "G11", 98, 2, 90, {10: (2.0, 0.0)})
    att = fuse.attach(s, fuse.Topology(chain(), set()))
    assert (att.way_id, att.direction, att.how) == (20, 1, "handed over")


def test_precise_bearing_prefers_the_path_it_fits():
    s = sign("precise", "G11", 0, 0, 37, {1: (2.0, 30.0), 2: (6.0, 3.0)})
    assert fuse.choose_way(s, {1, 2}) == 2
    q = sign("quantised", "G11", 0, 0, 0, {1: (2.0, 30.0), 2: (6.0, 3.0)})
    assert fuse.choose_way(q, {1, 2}) == 1


def test_supplementary_signs():
    assert fuse.sub_sign_effect("G11", {"supplementarySigns": [{"text": "Onleesbaar"}]}) == "unreadable"
    assert fuse.sub_sign_effect("G11", {"supplementarySigns": [{"text": "snorfiesten niet  toegestaan"}]}) == "confirms"
    assert fuse.sub_sign_effect("G13", {"supplementarySigns": [{"text": "dus niet brommen"}]}) == "confirms"
    assert fuse.sub_sign_effect("G11", {"supplementarySigns": [{"text": "speed-pedelecs toegestaan"}]}) is None
    assert fuse.sub_sign_effect("G12a", {"supplementarySigns": [{"text": "snorfietsen niet toegestaan"}]}) is None
    assert fuse.sub_sign_effect("G12a", {"supplementarySigns": [{"signCode": "OB505"}]}) is None


def test_unreadable_sign_gives_no_evidence_but_still_stops_propagation():
    signs = [
        sign("start", "G11", 3, 2, 90, {10: (2.0, 0.0)}),
        sign("unreadable", "G12a", 210, 2, 90, {30: (2.0, 0.0)}, texts=["onleesbaar"]),
    ]
    got, _ = statuses(chain(), signs)
    assert got == {10: FORBIDDEN, 20: FORBIDDEN, 30: UNKNOWN, 40: UNKNOWN}


def ndw(status, kind="direct", date="2025-06-01", trusted=False):
    return fuse.Evidence(status, "s1", date, kind, 0 if kind == "direct" else 1, False, trusted)


def override(status):
    return fuse.Override(way_id=1, status=status, reason="survey", date="2026-11-14", line=2)


@pytest.mark.parametrize(
    "osm, evidence, ovr, expected, source",
    [
        (ALLOWED, [ndw(ALLOWED)], override(FORBIDDEN), FORBIDDEN, fuse.SOURCE_OVERRIDE),
        (UNKNOWN, [ndw(ALLOWED)], override(FORBIDDEN), FORBIDDEN, fuse.SOURCE_OVERRIDE),
        (FORBIDDEN, [ndw(FORBIDDEN)], override(ALLOWED), ALLOWED, fuse.SOURCE_OVERRIDE),
        (ALLOWED, [ndw(FORBIDDEN)], None, ALLOWED, fuse.SOURCE_OSM),
        (ALLOWED, [ndw(FORBIDDEN, trusted=True)], None, FORBIDDEN, fuse.SOURCE_NDW_NEWER),
        (ALLOWED, [ndw(FORBIDDEN, trusted=True)], override(ALLOWED), ALLOWED, fuse.SOURCE_OVERRIDE),
        (ALLOWED, [ndw(FORBIDDEN, date="2019-01-01", trusted=True)], None, ALLOWED, fuse.SOURCE_OSM),
        (ALLOWED, [ndw(FORBIDDEN, date="", trusted=True)], None, ALLOWED, fuse.SOURCE_OSM),
        (ALLOWED, [ndw(FORBIDDEN, "propagated", trusted=True)], None, ALLOWED, fuse.SOURCE_OSM),
        (FORBIDDEN, [ndw(ALLOWED)], None, FORBIDDEN, fuse.SOURCE_OSM),
        (UNKNOWN, [ndw(FORBIDDEN)], None, FORBIDDEN, fuse.SOURCE_NDW_DIRECT),
        (UNKNOWN, [ndw(ALLOWED, "propagated")], None, ALLOWED, fuse.SOURCE_NDW_PROPAGATED),
        (UNKNOWN, [ndw(ALLOWED, "propagated"), ndw(FORBIDDEN)], None, FORBIDDEN, fuse.SOURCE_NDW_DIRECT),
        (UNKNOWN, [ndw(ALLOWED), ndw(FORBIDDEN)], None, UNKNOWN, ""),
        (UNKNOWN, [], None, UNKNOWN, ""),
    ],
)
def test_precedence(osm, evidence, ovr, expected, source):
    w = way(1, [1, 2], [(0, 0), (10, 0)], osm_status=osm)
    fused = fuse.fuse_way(w, evidence, ovr)
    assert (fused.status, fused.source) == (expected, source)


def test_osm_ndw_conflict_records_both_dates_and_ndw_newer_flag():
    w = way(1, [1, 2], [(0, 0), (10, 0)], osm_status=ALLOWED, timestamp="2023-10-29")
    fused = fuse.fuse_way(w, [ndw(FORBIDDEN, date="2025-09-09")], None)
    c = fuse.conflict_for(w, fused, None)
    assert (c["osm_date"], c["ndw_date"], c["ndw_newer"], c["winner"], c["final_status"]) == (
        "2023-10-29", "2025-09-09", True, "OSM", ALLOWED)
    assert "ambiguous" in c["reason"]

    older = fuse.fuse_way(w, [ndw(FORBIDDEN, date="2022-03-01", trusted=True)], None)
    c = fuse.conflict_for(w, older, None)
    assert (c["ndw_newer"], c["winner"], c["ndw_rule"]) == (False, "OSM", "OSM edit is newer than the NDW sign")

    newer = fuse.fuse_way(w, [ndw(FORBIDDEN, date="2025-09-09", trusted=True)], None)
    c = fuse.conflict_for(w, newer, None)
    assert (c["ndw_newer"], c["winner"], c["final_status"], c["ndw_rule"]) == (True, "NDW", FORBIDDEN, "NDW wins")


def test_sign_date_uses_field_dates_not_last_modified():
    assert fuse.sign_date({"lastModifiedOn": "2025-09-09", "registeredOn": "2016-04-19"}) == "2016-04-19"
    assert fuse.sign_date({"registeredOn": "2016-04-19", "validatedOn": "2025-01-02"}) == "2025-01-02"
    assert fuse.sign_date({"lastModifiedOn": "2025-09-09"}) == ""


def trust_case(candidates, registered="2024-03-01"):
    ways = chain()
    ways[20].osm_status = ALLOWED
    ways[20].timestamp = "2021-06-01"
    return statuses(ways, [sign("mid", "G11", 150, 2, 90, candidates, date="2025-09-09", registered=registered)])


def test_newer_unambiguous_ndw_sign_beats_older_osm_tag():
    got, result = trust_case({20: (2.0, 0.0)})
    assert got[20] == FORBIDDEN
    assert result["fused"][20].source == fuse.SOURCE_NDW_NEWER
    assert [c["winner"] for c in result["conflicts"]] == ["NDW"]


def test_newer_ndw_sign_with_a_competing_path_does_not_beat_osm():
    got, result = trust_case({20: (2.0, 0.0), 30: (12.0, 10.0)})
    assert got[20] == ALLOWED
    assert "another fitting cycle path" in result["conflicts"][0]["reason"]


def test_ndw_sign_with_an_uninterpreted_sub_sign_does_not_beat_osm():
    ways = chain()
    ways[20].osm_status = ALLOWED
    s = sign("mid", "G11", 150, 2, 90, {20: (2.0, 0.0)}, registered="2024-03-01")
    s.props["supplementarySigns"] = [{"signCode": "OB505"}]
    got, result = statuses(ways, [s])
    assert got[20] == ALLOWED
    assert "OB505" in result["conflicts"][0]["reason"]


def test_ndw_sign_far_from_the_path_does_not_beat_osm():
    got, _ = trust_case({20: (15.0, 0.0)})
    assert got[20] == ALLOWED


def test_ndw_record_only_newer_by_last_modified_does_not_beat_osm():
    got, result = trust_case({20: (2.0, 0.0)}, registered="2016-05-01")
    assert got[20] == ALLOWED
    assert result["conflicts"][0]["ndw_rule"] == "OSM edit is newer than the NDW sign"


def test_undated_ndw_record_does_not_win_on_recency():
    got, result = trust_case({20: (2.0, 0.0)}, registered="")
    assert got[20] == ALLOWED
    assert result["conflicts"][0]["ndw_rule"] == "NDW record has no placed, validated or registered date"


def test_override_beats_osm_and_ndw_end_to_end(tmp_path):
    csv_path = tmp_path / "overrides.csv"
    csv_path.write_text('way_id,status,reason,date\n20,forbidden,"surveyed, no G12a",2026-11-14\n')
    overrides = fuse.load_overrides(csv_path)
    ways = chain()
    ways[20].osm_status = ALLOWED
    got, result = statuses(ways, [sign("start", "G12a", 3, 2, 90, {10: (2.0, 0.0)})], overrides=overrides)
    assert got[20] == FORBIDDEN
    assert result["fused"][20].source == fuse.SOURCE_OVERRIDE
    assert [c["winner"] for c in result["conflicts"]] == ["override"]


def test_override_file_rejects_unknown_status(tmp_path):
    csv_path = tmp_path / "overrides.csv"
    csv_path.write_text("way_id,status,reason,date\n1,maybe,x,2026-11-14\n")
    with pytest.raises(ValueError, match="allowed or forbidden"):
        fuse.load_overrides(csv_path)
