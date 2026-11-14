from dataclasses import dataclass, field

from .classify import UNKNOWN


@dataclass
class CycleWay:
    id: int
    version: int
    timestamp: str
    tags: dict[str, str]
    coords: list[tuple[float, float]]
    length_m: float
    osm_status: str
    osm_reason: str
    node_ids: list[int] = field(default_factory=list)
    xy: list[tuple[float, float]] = field(default_factory=list)
    signs: list[str] = field(default_factory=list)
    nearby_any: set[str] = field(default_factory=set)
    ndw_status: str | None = None
    final_status: str = UNKNOWN
    final_source: str = ""


@dataclass
class Sign:
    id: str
    code: str
    lat: float
    lon: float
    x: float
    y: float
    bearing: float | None
    last_modified: str
    props: dict
    best_cycleway: tuple[float, int] | None = None
    best_cycleway_any_bearing: tuple[float, int] | None = None
    best_other: tuple[float, str, int, bool] | None = None
    candidates: dict[int, tuple[float, float]] = field(default_factory=dict)
