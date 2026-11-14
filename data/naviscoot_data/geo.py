import math

CENTER_LAT = 52.156
CENTER_LON = 5.387
RADIUS_M = 50_000

EARTH_RADIUS_M = 6_371_008.8
_M_PER_DEG_LAT = math.pi * EARTH_RADIUS_M / 180
_M_PER_DEG_LON = _M_PER_DEG_LAT * math.cos(math.radians(CENTER_LAT))


def haversine_m(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = p2 - p1
    dl = math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * EARTH_RADIUS_M * math.asin(math.sqrt(a))


def in_region(lat: float, lon: float, margin_m: float = 0) -> bool:
    return haversine_m(CENTER_LAT, CENTER_LON, lat, lon) <= RADIUS_M + margin_m


def region_bbox(margin_m: float = 0) -> tuple[float, float, float, float]:
    r = RADIUS_M + margin_m
    dlat = r / _M_PER_DEG_LAT
    dlon = r / (_M_PER_DEG_LAT * math.cos(math.radians(CENTER_LAT + dlat)))
    return CENTER_LAT - dlat, CENTER_LON - dlon, CENTER_LAT + dlat, CENTER_LON + dlon


def to_xy(lat: float, lon: float) -> tuple[float, float]:
    """Local equirectangular metres around the region centre; error is well under 1% within 60 km."""
    return (lon - CENTER_LON) * _M_PER_DEG_LON, (lat - CENTER_LAT) * _M_PER_DEG_LAT


def point_segment_distance(px: float, py: float, ax: float, ay: float, bx: float, by: float) -> float:
    dx, dy = bx - ax, by - ay
    seg2 = dx * dx + dy * dy
    t = 0.0 if seg2 == 0 else max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / seg2))
    return math.hypot(px - (ax + t * dx), py - (ay + t * dy))


def segment_bearing(ax: float, ay: float, bx: float, by: float) -> float:
    return math.degrees(math.atan2(bx - ax, by - ay)) % 360


def axis_difference(b1: float, b2: float) -> float:
    """Angle between two bearings treated as undirected lines, in [0, 90]."""
    d = abs(b1 - b2) % 180
    return min(d, 180 - d)
