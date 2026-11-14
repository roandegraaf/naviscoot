import os
from dataclasses import dataclass

import requests

DEFAULT_URL = os.environ.get("VALHALLA_URL", "http://127.0.0.1:8002")


@dataclass(frozen=True)
class Edge:
    way_id: int
    length_km: float
    speed: int
    speed_limit: int | None
    names: tuple[str, ...]
    begin_shape_index: int
    end_shape_index: int


@dataclass
class Route:
    length_km: float
    time_s: float
    shapes: list[str]
    edges: list[Edge]

    @property
    def way_ids(self) -> list[int]:
        return [e.way_id for e in self.edges]

    @property
    def names(self) -> set[str]:
        return {n for e in self.edges for n in e.names}


class ValhallaError(RuntimeError):
    pass


def _location(point: tuple[float, float], **extra) -> dict:
    return {"lat": point[0], "lon": point[1], **extra}


def _edge(raw: dict) -> Edge:
    return Edge(
        way_id=raw.get("way_id", 0),
        length_km=raw.get("length", 0.0),
        speed=raw.get("speed", 0),
        speed_limit=raw.get("speed_limit"),
        names=tuple(raw.get("names", [])),
        begin_shape_index=raw.get("begin_shape_index", 0),
        end_shape_index=raw.get("end_shape_index", 0),
    )


class Valhalla:
    def __init__(self, url: str = DEFAULT_URL, timeout: float = 120):
        self.url = url.rstrip("/")
        self.timeout = timeout

    def _post(self, action: str, body: dict) -> dict:
        resp = requests.post(f"{self.url}/{action}", json=body, timeout=self.timeout)
        data = resp.json()
        if resp.status_code != 200:
            raise ValhallaError(f"{action} {resp.status_code}: {data.get('error', data)}")
        return data

    def status(self) -> dict:
        return requests.get(f"{self.url}/status", timeout=10).json()

    def route(
        self,
        points: list[tuple[float, float]],
        costing: str = "motor_scooter",
        exclude: list[tuple[float, float]] | None = None,
        location_options: dict | None = None,
        costing_options: dict | None = None,
    ) -> Route:
        body = {
            "locations": [_location(p, **(location_options or {})) for p in points],
            "costing": costing,
            "directions_options": {"units": "kilometers"},
            "directions_type": "none",
            "date_time": {"type": 0},
        }
        if costing_options:
            body["costing_options"] = {costing: costing_options}
        if exclude:
            body["exclude_locations"] = [_location(p) for p in exclude]
        trip = self._post("route", body)["trip"]
        shapes = [leg["shape"] for leg in trip["legs"]]
        edges: list[Edge] = []
        for shape in shapes:
            edges.extend(self.edge_walk(shape, costing))
        summary = trip["summary"]
        return Route(summary["length"], summary["time"], shapes, edges)

    def edge_walk(self, encoded_shape: str, costing: str = "motor_scooter") -> list[Edge]:
        body = {
            "encoded_polyline": encoded_shape,
            "shape_match": "edge_walk",
            "costing": costing,
            "filters": {
                "attributes": [
                    "edge.way_id",
                    "edge.length",
                    "edge.speed",
                    "edge.speed_limit",
                    "edge.names",
                    "edge.begin_shape_index",
                    "edge.end_shape_index",
                ],
                "action": "include",
            },
        }
        return [_edge(e) for e in self._post("trace_attributes", body)["edges"]]

    def map_match(
        self, points: list[tuple[float, float]], costing: str = "motor_scooter", search_radius: float = 15
    ) -> list[Edge]:
        body = {
            "shape": [_location(p) for p in points],
            "shape_match": "map_snap",
            "costing": costing,
            "trace_options": {"search_radius": search_radius},
            "filters": {
                "attributes": ["edge.way_id", "edge.length", "edge.speed", "edge.speed_limit", "edge.names"],
                "action": "include",
            },
        }
        return [_edge(e) for e in self._post("trace_attributes", body)["edges"]]


def _edge_midpoints(route: Route, way_ids: set[int]) -> list[tuple[float, float]]:
    """Midpoints of edges on the given ways, except the first and last edge: the rider starts and ends there."""
    points = []
    last = len(route.edges) - 1
    edges = iter(enumerate(route.edges))
    for shape in route.shapes:
        coords = decode_polyline6(shape)
        for index, edge in edges:
            if edge.way_id in way_ids and 0 < index < last:
                begin, end = edge.begin_shape_index, edge.end_shape_index
                a, b = coords[(begin + end) // 2], coords[(begin + end + 1) // 2]
                points.append(((a[0] + b[0]) / 2, (a[1] + b[1]) / 2))
            if edge.end_shape_index == len(coords) - 1:
                break
    return points


def verified_only_route(
    client: Valhalla, points: list[tuple[float, float]], unverified_ids: set[int], max_requests: int = 15
) -> tuple[Route, int]:
    exclude: list[tuple[float, float]] = []
    for request in range(1, max_requests + 1):
        route = client.route(points, exclude=exclude)
        midpoints = _edge_midpoints(route, unverified_ids)
        if not midpoints:
            return route, request
        exclude.extend(midpoints)
    raise ValhallaError(f"verified-only route not found within {max_requests} requests")


def decode_polyline6(encoded: str) -> list[tuple[float, float]]:
    coords: list[tuple[float, float]] = []
    index = lat = lon = 0
    while index < len(encoded):
        for axis in (0, 1):
            shift = result = 0
            while True:
                b = ord(encoded[index]) - 63
                index += 1
                result |= (b & 0x1F) << shift
                shift += 5
                if b < 0x20:
                    break
            delta = ~(result >> 1) if result & 1 else result >> 1
            if axis == 0:
                lat += delta
            else:
                lon += delta
        coords.append((lat / 1e6, lon / 1e6))
    return coords
