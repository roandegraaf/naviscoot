#!/usr/bin/env python3
"""Recolours OpenFreeMap Liberty into Naviscoot's night map: make_night_style.py [liberty.json].

Major roads stay a muted khaki so they never read as the orange dashed "unverified" route line on top.
"""

import json
import pathlib
import sys
import urllib.request

LIBERTY_URL = "https://tiles.openfreemap.org/styles/liberty"
OUTPUT = pathlib.Path(__file__).resolve().parents[2] / "Naviscoot" / "Resources" / "liberty-night.json"

GROUND = "#1a1f29"
HALO = GROUND
CASING = "#10141b"

MINOR = "#5c5953"
SERVICE = "#4a4945"
MAJOR = "#8f8160"
TRUNK = "#a38e5f"
MOTORWAY = "#b39259"
PATH = "#77726a"
RAIL = "#5f6672"

TUNNEL_MINOR = "#3f3e3b"
TUNNEL_MAJOR = "#655c47"
TUNNEL_MOTORWAY = "#7a6744"

ROAD_FILLS = {
    "motorway_link": MOTORWAY,
    "motorway": MOTORWAY,
    "trunk_primary": TRUNK,
    "secondary_tertiary": MAJOR,
    "link": MAJOR,
    "minor": MINOR,
    "street": MINOR,
    "service_track": SERVICE,
}

TUNNEL_FILLS = {
    "motorway_link": TUNNEL_MOTORWAY,
    "motorway": TUNNEL_MOTORWAY,
    "trunk_primary": TUNNEL_MAJOR,
    "secondary_tertiary": TUNNEL_MAJOR,
    "link": TUNNEL_MAJOR,
    "minor": TUNNEL_MINOR,
    "service_track": TUNNEL_MINOR,
}

FIXED = {
    "background": {"background-color": GROUND},
    "natural_earth": {"raster-brightness-max": 0.3},
    "park": {"fill-color": "#1c3026", "fill-outline-color": "#284a36"},
    "park_outline": {"line-color": "#284a36"},
    "landuse_residential": {"fill-color": ["interpolate", ["linear"], ["zoom"], 9, "rgba(40,46,58,0.8)", 12, "rgba(36,42,54,0.6)"]},
    "landcover_wood": {"fill-color": "#1f3a2b", "fill-opacity": 0.6},
    "landcover_grass": {"fill-color": "#22392b", "fill-opacity": 0.5},
    "landcover_ice": {"fill-color": "#2a3340"},
    "landcover_wetland": {"fill-color": "#1c2f2b", "fill-opacity": 0.6},
    "landuse_pitch": {"fill-color": "#21342a"},
    "landuse_track": {"fill-color": "#21342a"},
    "landuse_cemetery": {"fill-color": "#22302a"},
    "landuse_hospital": {"fill-color": "#33252d"},
    "landuse_school": {"fill-color": "#2c2d25"},
    "waterway_tunnel": {"line-color": "#1f4a70"},
    "waterway_river": {"line-color": "#24557f"},
    "waterway_other": {"line-color": "#24557f"},
    "water": {"fill-color": "#13324f"},
    "landcover_sand": {"fill-color": "#2d2b24"},
    "aeroway_fill": {"fill-color": "#262c36"},
    "aeroway_runway": {"line-color": "#3a414c"},
    "aeroway_taxiway": {"line-color": "#3a414c"},
    "road_area_pattern": {"fill-color": "#2a2f38"},
    "building": {"fill-color": "#343b47", "fill-outline-color": "#262c36"},
    "building-3d": {"fill-extrusion-color": "#4b5361", "fill-extrusion-opacity": 0.9},
    "boundary_3": {"line-color": "#6b7280"},
    "boundary_2": {"line-color": "#8b93a1"},
    "boundary_disputed": {"line-color": "#8b93a1"},
    "waterway_line_label": {"text-color": "#7fa9d6", "text-halo-color": HALO},
    "water_name_point_label": {"text-color": "#7fa9d6", "text-halo-color": HALO},
    "water_name_line_label": {"text-color": "#7fa9d6", "text-halo-color": HALO},
    "poi_r20": {"text-color": "#a9b1bd", "text-halo-color": HALO},
    "poi_r7": {"text-color": "#a9b1bd", "text-halo-color": HALO},
    "poi_r1": {"text-color": "#a9b1bd", "text-halo-color": HALO},
    "poi_transit": {"text-color": "#8fb4d9", "text-halo-color": HALO},
    "airport": {"text-color": "#a9b1bd", "text-halo-color": HALO},
    "highway-name-path": {"text-color": "#a29c92", "text-halo-color": HALO, "text-halo-width": 1},
    "highway-name-minor": {"text-color": "#d3d6db", "text-halo-color": HALO, "text-halo-width": 1.2},
    "highway-name-major": {"text-color": "#e2e4e8", "text-halo-color": HALO, "text-halo-width": 1.2},
    "label_other": {"text-color": "#c3c8cf", "text-halo-color": HALO},
    "label_village": {"text-color": "#e4e7eb", "text-halo-color": HALO},
    "label_town": {"text-color": "#e4e7eb", "text-halo-color": HALO},
    "label_state": {"text-color": "#c3c8cf", "text-halo-color": HALO},
    "label_city": {"text-color": "#eef0f3", "text-halo-color": HALO},
    "label_city_capital": {"text-color": "#eef0f3", "text-halo-color": HALO},
    "label_country_3": {"text-color": "#eef0f3", "text-halo-color": HALO},
    "label_country_2": {"text-color": "#eef0f3", "text-halo-color": HALO},
    "label_country_1": {"text-color": "#eef0f3", "text-halo-color": HALO},
}

DROPPED_PAINT = {"landcover_wetland": ["fill-pattern"], "road_area_pattern": ["fill-pattern"]}

COLOUR_KEYS = ("color",)


def road_paint(layer_id):
    for prefix in ("tunnel_", "road_", "bridge_"):
        if not layer_id.startswith(prefix):
            continue
        rest = layer_id[len(prefix):]
        if rest.endswith("_rail") or rest.endswith("_rail_hatching"):
            return {"line-color": RAIL}
        if rest.endswith("_casing"):
            return {"line-color": CASING}
        if rest == "path_pedestrian":
            return {"line-color": "#57534c" if prefix == "tunnel_" else PATH}
        fills = TUNNEL_FILLS if prefix == "tunnel_" else ROAD_FILLS
        if rest in fills:
            return {"line-color": fills[rest]}
    return None


def has_colour(paint):
    return any(key.endswith(COLOUR_KEYS) for key in paint)


def night(liberty):
    style = json.loads(json.dumps(liberty))
    style["name"] = "Naviscoot Night"
    unknown = []
    for layer in style["layers"]:
        layer_id = layer["id"]
        paint = layer.setdefault("paint", {})
        for key in DROPPED_PAINT.get(layer_id, []):
            paint.pop(key, None)
        override = FIXED.get(layer_id) or road_paint(layer_id)
        if override is None:
            if has_colour(paint):
                unknown.append(layer_id)
            continue
        paint.update(override)
        if layer["type"] == "symbol" and "text-halo-color" not in paint and "text-field" in layer.get("layout", {}):
            paint["text-halo-color"] = HALO
    if unknown:
        sys.exit(f"Liberty has coloured layers without a night colour: {', '.join(unknown)}")
    return style


def main():
    if len(sys.argv) > 1:
        liberty = json.loads(pathlib.Path(sys.argv[1]).read_text())
    else:
        request = urllib.request.Request(LIBERTY_URL, headers={"User-Agent": "naviscoot-style-builder"})
        with urllib.request.urlopen(request) as response:
            liberty = json.load(response)
    OUTPUT.write_text(json.dumps(night(liberty), indent=1) + "\n")
    print(f"wrote {OUTPUT}")


if __name__ == "__main__":
    main()
