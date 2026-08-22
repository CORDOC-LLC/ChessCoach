#!/usr/bin/env python3
"""One-off conversion of the vendored Cburnett piece SVGs
(Sources/GemmaChessCore/Resources/Pieces.xcassets/*.imageset/*.svg) into Android
VectorDrawable XML (android/app/src/main/res/drawable/piece_*.xml).

SVG path data ('d') uses the same command grammar as Android's pathData, so paths
are copied verbatim; only presentation attributes (fill/stroke/stroke-width),
which SVG lets a <g> set for its children, are resolved and written explicitly
per <path> since VectorDrawable has no group-level style inheritance for these.
"""
import re
import xml.etree.ElementTree as ET
from pathlib import Path

SVG_NS = "http://www.w3.org/2000/svg"
SRC = Path("/home/user/ChessCoach/Sources/GemmaChessCore/Resources/Pieces.xcassets")
DEST = Path("/home/user/ChessCoach/android/app/src/main/res/drawable")

PIECES = ["wP", "wN", "wB", "wR", "wQ", "wK", "bP", "bN", "bB", "bR", "bQ", "bK"]

NONE = "none"


def resolve(attr, own, inherited, default):
    return own.get(attr, inherited.get(attr, default))


def convert(svg_path: Path, out_path: Path):
    tree = ET.parse(svg_path)
    root = tree.getroot()
    vb = root.get("viewBox").split()
    w, h = vb[2], vb[3]

    lines = [
        '<vector xmlns:android="http://schemas.android.com/apk/res/android"',
        f'    android:width="{w}dp"',
        f'    android:height="{h}dp"',
        f'    android:viewportWidth="{w}"',
        f'    android:viewportHeight="{h}">',
    ]

    def walk(el, inherited):
        style = dict(inherited)
        for attr in ("fill", "stroke", "stroke-width", "fill-rule"):
            if attr in el.attrib:
                style[attr] = el.attrib[attr]
        tag = el.tag.split("}")[-1]
        if tag == "path":
            d = el.get("d")
            fill = resolve("fill", el.attrib, inherited, "#000000")
            stroke = resolve("stroke", el.attrib, inherited, NONE)
            stroke_width = resolve("stroke-width", el.attrib, inherited, "0")
            lines.append(f'    <path')
            lines.append(f'        android:pathData="{d}"')
            if fill != NONE:
                lines.append(f'        android:fillColor="{fill}"')
            if stroke != NONE:
                lines.append(f'        android:strokeColor="{stroke}"')
                lines.append(f'        android:strokeWidth="{stroke_width}"')
                lines.append(f'        android:strokeLineCap="round"')
                lines.append(f'        android:strokeLineJoin="round"')
            lines.append('        />')
        for child in el:
            walk(child, style)

    walk(root, {})
    lines.append('</vector>')
    out_path.write_text("\n".join(lines) + "\n")


DEST.mkdir(parents=True, exist_ok=True)
for piece in PIECES:
    svg = SRC / f"{piece}.imageset" / f"{piece}.svg"
    out = DEST / f"piece_{piece.lower()}.xml"
    convert(svg, out)
    print(f"wrote {out}")
