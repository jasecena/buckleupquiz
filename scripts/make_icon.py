#!/usr/bin/env python3
"""Generate the app icon: App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png

A placeholder until the real mascot exists (STAGES M3): a white speech bubble
with a question mark on a warm orange gradient. It is original and not a seatbelt
(FEATURES §0).

Same approach as the activity-tracker app: no Pillow or ImageMagick. Shapes are
signed distance fields (one sample per pixel, antialiased), and the PNG is written
by hand with zlib + CRC32. App Store icons must be opaque, so the output is RGB
with no alpha.

Usage: python3 scripts/make_icon.py
"""
from __future__ import annotations

import math
import struct
import zlib
from pathlib import Path

SIZE = 1024
OUT = Path(__file__).resolve().parent.parent / "App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"

BG_TOP = (0xFF, 0x9A, 0x4D)
BG_BOTTOM = (0xFF, 0x5E, 0x1A)
BUBBLE = (0xFF, 0xFF, 0xFF)
GLYPH = (0x1A, 0x1B, 0x30)
SHADOW = (0xC9, 0x44, 0x0A)


def sd_round_box(px, py, cx, cy, hx, hy, r):
    qx, qy = abs(px - cx) - hx + r, abs(py - cy) - hy + r
    return math.hypot(max(qx, 0), max(qy, 0)) + min(max(qx, qy), 0) - r


def sd_circle(px, py, cx, cy, r):
    return math.hypot(px - cx, py - cy) - r


def sd_capsule(px, py, ax, ay, bx, by, r):
    pax, pay, bax, bay = px - ax, py - ay, bx - ax, by - ay
    h = max(0.0, min(1.0, (pax * bax + pay * bay) / (bax * bax + bay * bay)))
    return math.hypot(pax - bax * h, pay - bay * h) - r


def sd_triangle(px, py, pts):
    # Exact SDF for a triangle (Inigo Quilez), y-down coordinates.
    (x0, y0), (x1, y1), (x2, y2) = pts
    edges = [(x1 - x0, y1 - y0), (x2 - x1, y2 - y1), (x0 - x2, y0 - y2)]
    verts = [(px - x0, py - y0), (px - x1, py - y1), (px - x2, py - y2)]
    s = math.copysign(1.0, edges[0][0] * edges[2][1] - edges[0][1] * edges[2][0])
    dist2, side = float("inf"), float("inf")
    for (ex, ey), (vx, vy) in zip(edges, verts):
        h = max(0.0, min(1.0, (vx * ex + vy * ey) / (ex * ex + ey * ey)))
        qx, qy = vx - ex * h, vy - ey * h
        dist2 = min(dist2, qx * qx + qy * qy)
        side = min(side, s * (vx * ey - vy * ex))
    return -math.sqrt(dist2) * math.copysign(1.0, side)


def sd_arc(px, py, cx, cy, radius, thickness, end_angle):
    """Ring from angle -pi (left) over the top to `end_angle` (y-down), round caps."""
    a = math.atan2(py - cy, px - cx)
    if a <= end_angle:
        return abs(math.hypot(px - cx, py - cy) - radius) - thickness
    ends = [(cx - radius, cy), (cx + radius * math.cos(end_angle), cy + radius * math.sin(end_angle))]
    return min(math.hypot(px - ex, py - ey) for ex, ey in ends) - thickness


def bubble(px, py):
    body = sd_round_box(px, py, 0.5, 0.47, 0.31, 0.27, 0.13)
    tail = sd_triangle(px, py, [(0.27, 0.62), (0.43, 0.70), (0.22, 0.86)])
    return min(body, tail)


def question_mark(px, py):
    t = 0.042
    end = math.pi / 2
    cx, cy, r = 0.5, 0.375, 0.095
    arc = sd_arc(px, py, cx, cy, r, t, end)
    ex, ey = cx + r * math.cos(end), cy + r * math.sin(end)
    stem = sd_capsule(px, py, ex, ey, 0.5, 0.535, t)
    dot = sd_circle(px, py, 0.5, 0.655, 0.046)
    return min(arc, stem, dot)


def coverage(d):
    return max(0.0, min(1.0, 0.5 - d * SIZE))


def mix(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def render() -> bytes:
    rows = []
    for j in range(SIZE):
        py = (j + 0.5) / SIZE
        row = bytearray([0])  # PNG filter: none
        bg = mix(BG_TOP, BG_BOTTOM, py)
        for i in range(SIZE):
            px = (i + 0.5) / SIZE
            color = bg
            shadow = coverage(bubble(px - 0.012, py - 0.018) - 0.004) * 0.35
            if shadow:
                color = mix(color, SHADOW, shadow)
            b = coverage(bubble(px, py))
            if b:
                color = mix(color, BUBBLE, b)
                g = coverage(question_mark(px, py))
                if g:
                    color = mix(color, GLYPH, g)
            row.extend(color)
        rows.append(bytes(row))
    return b"".join(rows)


def png(raw: bytes) -> bytes:
    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
    header = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0)  # 8-bit RGB, no alpha
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")


def main() -> None:
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_bytes(png(render()))
    (OUT.parent / "Contents.json").write_text(
        '{\n  "images" : [\n    {\n      "filename" : "AppIcon-1024.png",\n      "idiom" : "universal",\n'
        '      "platform" : "ios",\n      "size" : "1024x1024"\n    }\n  ],\n'
        '  "info" : {\n    "author" : "xcode",\n    "version" : 1\n  }\n}\n'
    )
    print(f"wrote {OUT.relative_to(Path.cwd()) if OUT.is_relative_to(Path.cwd()) else OUT}")


if __name__ == "__main__":
    main()
