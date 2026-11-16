#!/usr/bin/env python3
"""Writes the icon concepts as SVG and renders them to PNG.

Needs rsvg-convert and ImageMagick 7 (`brew install librsvg imagemagick`).
Run from anywhere: `python3 ios/Design/icon/render.py`.
"""

import json
import shutil
import subprocess
from pathlib import Path

DEFAULT_CONCEPT = "route"

HERE = Path(__file__).resolve().parent
SVG_DIR = HERE / "svg"
PNG_DIR = HERE / "png"
ASSETS = HERE.parent.parent / "Naviscoot" / "Resources" / "Assets.xcassets"

BLUE = "#0B5FD9"
BLUE_TOP = "#2B7BEF"
BLUE_DARK_MODE = "#3B82F6"
BLUE_LIGHT = "#8AB8FF"
INK = "#111827"
INK_TOP = "#1F2937"
SURFACE_DARK = "#1B212B"
SCREEN_LIGHT = "#FFFFFF"
SCREEN_DARK = "#0F141B"
WHITE = "#FFFFFF"
GREY = "#B8B8B8"

ICON_SIZE = 1024
CORNER_RADIUS = 229
LAUNCH_POINTS = 128

ARROW = "512,150 650,388 512,334 374,388"
START = (420, 830)
ROUTE = "M 420 830 C 420 720, 620 720, 620 610 C 620 528, 512 528, 512 446"
BIG_ARROW = "512,212 724,786 512,668 300,786"
PIN = (
    "M 512 860 C 444 748, 290 636, 290 452 "
    "A 222 222 0 1 1 734 452 C 734 636, 580 748, 512 860 Z"
)
CHECK = "M 414 452 L 488 526 L 616 392"

VARIANTS = {
    "route": {
        "light": {"bg": (BLUE_TOP, BLUE), "route": WHITE, "arrow": WHITE},
        "dark": {"bg": None, "route": BLUE_DARK_MODE, "arrow": BLUE_LIGHT},
        "tinted": {"bg": None, "route": GREY, "arrow": WHITE},
    },
    "arrow": {
        "light": {"bg": (INK_TOP, INK), "arrow": (BLUE_DARK_MODE, BLUE), "ring": WHITE},
        "dark": {"bg": None, "arrow": (BLUE_LIGHT, BLUE_DARK_MODE), "ring": BLUE_DARK_MODE},
        "tinted": {"bg": None, "arrow": (WHITE, WHITE), "ring": GREY},
    },
    "pin": {
        "light": {"bg": (BLUE_TOP, BLUE), "pin": WHITE},
        "dark": {"bg": None, "pin": BLUE_DARK_MODE},
        "tinted": {"bg": None, "pin": WHITE},
    },
}


def gradient(gid, colours):
    top, bottom = colours
    return (
        f'<linearGradient id="{gid}" x1="0" y1="0" x2="0" y2="1">'
        f'<stop offset="0" stop-color="{top}"/><stop offset="1" stop-color="{bottom}"/>'
        "</linearGradient>"
    )


def background(colours):
    if colours is None:
        return "", ""
    return gradient("bg", colours), f'<rect width="{ICON_SIZE}" height="{ICON_SIZE}" fill="url(#bg)"/>'


def route_mark(p):
    x, y = START
    defs = (
        '<mask id="hole" maskUnits="userSpaceOnUse" x="0" y="0" width="1024" height="1024">'
        '<rect width="1024" height="1024" fill="#fff"/>'
        f'<circle cx="{x}" cy="{y}" r="26" fill="#000"/>'
        "</mask>"
    )
    body = (
        f'<g mask="url(#hole)">'
        f'<path d="{ROUTE}" fill="none" stroke="{p["route"]}" stroke-width="80" stroke-linecap="round"/>'
        f'<circle cx="{x}" cy="{y}" r="64" fill="{p["route"]}"/>'
        "</g>"
        f'<polygon points="{ARROW}" fill="{p["arrow"]}" stroke="{p["arrow"]}" '
        'stroke-width="12" stroke-linejoin="round"/>'
    )
    return defs, body


def arrow_mark(p):
    defs = gradient("arrowfill", p["arrow"])
    body = (
        f'<circle cx="512" cy="512" r="376" fill="none" stroke="{p["ring"]}" '
        'stroke-width="24" stroke-opacity="0.9"/>'
        f'<polygon points="{BIG_ARROW}" fill="url(#arrowfill)" stroke="url(#arrowfill)" '
        'stroke-width="16" stroke-linejoin="round"/>'
    )
    return defs, body


def pin_mark(p):
    defs = (
        '<mask id="cut" maskUnits="userSpaceOnUse" x="0" y="0" width="1024" height="1024">'
        '<rect width="1024" height="1024" fill="#fff"/>'
        f'<path d="{CHECK}" fill="none" stroke="#000" stroke-width="64" '
        'stroke-linecap="round" stroke-linejoin="round"/>'
        "</mask>"
    )
    body = f'<path d="{PIN}" fill="{p["pin"]}" mask="url(#cut)"/>'
    return defs, body


MARKS = {"route": route_mark, "arrow": arrow_mark, "pin": pin_mark}


def icon_svg(concept, variant, tile=None):
    p = VARIANTS[concept][variant]
    bg_defs, bg_body = background(p["bg"])
    mark_defs, mark_body = MARKS[concept](p)
    clip_defs, open_group, close_group = "", "<g>", "</g>"
    tile_body = ""
    if tile is not None:
        clip_defs = (
            f'<clipPath id="tile"><rect width="{ICON_SIZE}" height="{ICON_SIZE}" '
            f'rx="{CORNER_RADIUS}"/></clipPath>'
        )
        open_group = '<g clip-path="url(#tile)">'
        tile_body = f'<rect width="{ICON_SIZE}" height="{ICON_SIZE}" fill="{tile}"/>'
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{ICON_SIZE}" height="{ICON_SIZE}" '
        f'viewBox="0 0 {ICON_SIZE} {ICON_SIZE}">'
        f"<defs>{bg_defs}{mark_defs}{clip_defs}</defs>"
        f"{open_group}{tile_body}{bg_body}{mark_body}{close_group}"
        "</svg>\n"
    )


def run(*args):
    subprocess.run([str(a) for a in args], check=True)


def render(svg_path, png_path, size, opaque_over=None):
    run("rsvg-convert", "-w", size, "-h", size, "-o", png_path, svg_path)
    if opaque_over is not None:
        run("magick", png_path, "-background", opaque_over, "-alpha", "remove", "-alpha", "off", png_path)


def write_svg(name, text):
    path = SVG_DIR / f"{name}.svg"
    path.write_text(text)
    return path


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2) + "\n")


def appearance(value):
    return [{"appearance": "luminosity", "value": value}]


def render_concepts():
    for concept in VARIANTS:
        for variant in ("light", "dark", "tinted"):
            svg = write_svg(f"{concept}-{variant}", icon_svg(concept, variant))
            opaque = VARIANTS[concept][variant]["bg"][1] if variant == "light" else None
            render(svg, PNG_DIR / f"{concept}-{variant}.png", ICON_SIZE, opaque)


def write_app_icon():
    iconset = ASSETS / "AppIcon.appiconset"
    iconset.mkdir(parents=True, exist_ok=True)
    images = []
    for variant in ("light", "dark", "tinted"):
        filename = f"AppIcon-{variant}.png"
        shutil.copyfile(PNG_DIR / f"{DEFAULT_CONCEPT}-{variant}.png", iconset / filename)
        image = {"filename": filename, "idiom": "universal", "platform": "ios", "size": "1024x1024"}
        if variant != "light":
            image = {"appearances": appearance(variant), **image}
        images.append(image)
    write_json(iconset / "Contents.json", {"images": images, "info": {"author": "xcode", "version": 1}})


def write_launch_assets():
    imageset = ASSETS / "LaunchMark.imageset"
    imageset.mkdir(parents=True, exist_ok=True)
    images = []
    tiles = {"light": None, "dark": SURFACE_DARK}
    for variant, tile in tiles.items():
        svg = write_svg(f"launch-{variant}", icon_svg(DEFAULT_CONCEPT, variant, tile=tile or "none"))
        for scale in (2, 3):
            filename = f"LaunchMark-{variant}@{scale}x.png"
            render(svg, imageset / filename, LAUNCH_POINTS * scale)
            image = {"filename": filename, "idiom": "universal", "scale": f"{scale}x"}
            if variant == "dark":
                image = {"appearances": appearance("dark"), **image}
            images.append(image)
    write_json(imageset / "Contents.json", {"images": images, "info": {"author": "xcode", "version": 1}})

    def components(hex_colour):
        h = hex_colour.lstrip("#")
        return {
            "alpha": "1.000",
            "red": f"0x{h[0:2]}",
            "green": f"0x{h[2:4]}",
            "blue": f"0x{h[4:6]}",
        }

    colours = [
        {"color": {"color-space": "srgb", "components": components(SCREEN_LIGHT)}, "idiom": "universal"},
        {
            "appearances": appearance("dark"),
            "color": {"color-space": "srgb", "components": components(SCREEN_DARK)},
            "idiom": "universal",
        },
    ]
    write_json(
        ASSETS / "LaunchBackground.colorset" / "Contents.json",
        {"colors": colours, "info": {"author": "xcode", "version": 1}},
    )
    write_json(ASSETS / "Contents.json", {"info": {"author": "xcode", "version": 1}})


def write_contact_sheet():
    previews = []
    for concept in VARIANTS:
        for variant, backdrop in (("light", "#F2F2F7"), ("dark", "#1C1C1E"), ("tinted", "#1C1C1E")):
            out = PNG_DIR / f"preview-{concept}-{variant}.png"
            tile = f"roundrectangle 0,0 1023,1023 {CORNER_RADIUS},{CORNER_RADIUS}"
            run(
                "magick", "-size", "1024x1024", "xc:none", "-fill", backdrop, "-draw", tile,
                PNG_DIR / f"{concept}-{variant}.png", "-compose", "Over", "-composite",
                "(", "-size", "1024x1024", "xc:none", "-fill", "white", "-draw", tile, ")",
                "-compose", "DstIn", "-composite", "-resize", "256x256", out,
            )
            if variant == "tinted":
                run("magick", out, "-fill", "#F5A623", "-tint", "100", out)
            previews.append(out)
    run(
        "magick", "montage", *previews, "-tile", "3x", "-geometry", "256x256+24+24",
        "-background", "#6B7280", PNG_DIR / "concepts.png",
    )
    for preview in previews:
        preview.unlink()


def main():
    SVG_DIR.mkdir(exist_ok=True)
    PNG_DIR.mkdir(exist_ok=True)
    render_concepts()
    write_app_icon()
    write_launch_assets()
    write_contact_sheet()


if __name__ == "__main__":
    main()
