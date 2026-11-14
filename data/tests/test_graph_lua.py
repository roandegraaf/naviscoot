import os
import subprocess

import osmium
import pytest

from naviscoot_data import paths
from naviscoot_data.valhalla import Valhalla, ValhallaError

pytestmark = pytest.mark.docker

FIXTURE_OSM = paths.REPO_DIR / "routing" / "test" / "fixture.osm"
FIXTURE_DIR = paths.REPO_DIR / "routing" / "build" / "fixture"
FIXTURE_PBF = FIXTURE_DIR / "fixture.osm.pbf"
GRAPHS = {"stock": ("stock", 8102), "patched": ("routing/valhalla/graph.lua", 8103)}
NEAR = {"minimum_reachability": 0, "radius": 5}


def _run(script: str, env: dict[str, str], *args: str) -> None:
    subprocess.run([str(paths.REPO_DIR / "routing" / script), *args], env={**os.environ, **env}, check=True,
                   capture_output=True, text=True)


@pytest.fixture(scope="module")
def graphs():
    FIXTURE_DIR.mkdir(parents=True, exist_ok=True)
    with osmium.SimpleWriter(str(FIXTURE_PBF), overwrite=True) as writer:
        for obj in osmium.FileProcessor(str(FIXTURE_OSM)):
            writer.add(obj)
    clients = {}
    for name, (lua, port) in GRAPHS.items():
        env = {"OUT": f"routing/build/fixture/{name}", "GRAPH_LUA": lua, "USE_ADMINS": "0",
               "PBF": "routing/build/fixture/fixture.osm.pbf", "NAME": f"naviscoot-fixture-{name}", "PORT": str(port)}
        _run("build.sh", env, "all")
        _run("serve.sh", env, "start")
        clients[name] = Valhalla(f"http://127.0.0.1:{port}")
    yield clients
    for name, (_, port) in GRAPHS.items():
        _run("serve.sh", {"NAME": f"naviscoot-fixture-{name}"}, "stop")


def _ride(client: Valhalla, lat: float, east_lon: float) -> list[int]:
    return client.route([(lat, 4.9975), (lat, east_lon)], location_options=NEAR).way_ids


def _match(client: Valhalla, lat: float, lons: list[float]):
    return client.map_match([(lat, lon) for lon in lons])


def test_use_sidepath_closes_the_carriageway(graphs):
    assert 1002 in _ride(graphs["stock"], 52.00, 5.0175)
    patched = _ride(graphs["patched"], 52.00, 5.0175)
    assert 1002 not in patched and 1003 in patched
    with pytest.raises(ValhallaError):
        _match(graphs["patched"], 52.00, [5.0005, 5.005, 5.01, 5.0145])


def test_mofa_grants_no_moped_access(graphs):
    assert 2002 in _ride(graphs["stock"], 52.02, 5.0125)
    patched = _ride(graphs["patched"], 52.02, 5.0125)
    assert 2002 not in patched and 2003 in patched
    with pytest.raises(ValhallaError):
        _match(graphs["patched"], 52.02, [5.0005, 5.005, 5.0095])


def test_unverified_path_is_open_but_slow(graphs):
    edges = _match(graphs["patched"], 52.04, [5.0005, 5.003, 5.006, 5.0095])
    assert [(e.way_id, e.speed, e.speed_limit) for e in edges] == [(3002, 15, 40)]
    assert 3003 in _ride(graphs["patched"], 52.04, 5.0125)


def test_moped_path_speeds(graphs):
    stock = {e.way_id: e.speed for e in graphs["stock"].route([(52.06, 4.9975), (52.06, 5.0225)], location_options=NEAR).edges}
    assert stock[4002] < 30 and stock[4003] < 30
    patched = graphs["patched"].route([(52.06, 4.9975), (52.06, 5.0225)], location_options=NEAR).edges
    by_way = {e.way_id: (e.speed, e.speed_limit) for e in patched}
    assert by_way[4002] == (40, 40)
    assert by_way[4003] == (30, 30)


def test_autoweg_is_closed(graphs):
    patched = _ride(graphs["patched"], 52.08, 5.0175)
    assert 5002 not in patched and 5003 in patched
    with pytest.raises(ValhallaError):
        _match(graphs["patched"], 52.08, [5.0005, 5.005, 5.01, 5.0145])


def test_bollard_does_not_close_a_moped_path(graphs):
    assert 6002 not in _ride(graphs["stock"], 52.10, 5.0125)
    patched = _ride(graphs["patched"], 52.10, 5.0125)
    assert 6002 in patched and 6003 not in patched
