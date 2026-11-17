#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Draws DroidNest's own app icon: src/app/DroidNest/Assets.xcassets/AppIcon.appiconset/Icon-1024.png.

It is DroidNest's, not Husk's: Husk's is a purple Android head over a lens, and this one is the same family of shapes with
DroidNest's own idea behind it -- a nest, and one game sitting in it. The nest is the arc under everything; the game is the
square tile that a launcher puts on a Home Screen, drawn as if it had just been set down; the two pips at the top are the
ears of the head Husk's icon is, kept only as a nod to where the code came from.

Written by hand rather than with PIL or a drawing library, so it needs nothing but Python 3 to regenerate: a 1024x1024
image, every pixel computed here, saved as a PNG with zlib. Run it after changing the colours:

    python3 scripts/make_droidnest_icon.py
"""
import math
import os
import struct
import zlib

SIZE = 1024
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..",
                   "src", "app", "DroidNest", "Assets.xcassets", "AppIcon.appiconset", "Icon-1024.png")

# The palette: deep indigo ground, a violet nest, a warm tile for the game, and one lit rim for the whole thing.
TOP = (0.42, 0.35, 0.95)
BOTTOM = (0.16, 0.11, 0.55)
NEST = (0.72, 0.60, 1.00)
NEST_DARK = (0.36, 0.26, 0.78)
TILE = (0.99, 0.98, 1.00)
TILE_SHADE = (0.80, 0.76, 0.98)
PIP = (0.98, 0.96, 1.00)


def clamp(v, lo=0.0, hi=1.0):
    return lo if v < lo else hi if v > hi else v


def mix(a, b, t):
    t = clamp(t)
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def over(dst, src, alpha):
    """Source over destination, in straight (unpremultiplied) colour."""
    alpha = clamp(alpha)
    return tuple(src[i] * alpha + dst[i] * (1 - alpha) for i in range(3))


def smoothstep(edge0, edge1, x):
    t = clamp((x - edge0) / (edge1 - edge0))
    return t * t * (3 - 2 * t)


def rounded_box(x, y, cx, cy, half, radius):
    """Distance from (x, y) to the edge of a rounded box: negative inside."""
    dx = abs(x - cx) - (half - radius)
    dy = abs(y - cy) - (half - radius)
    outside = math.hypot(max(dx, 0.0), max(dy, 0.0))
    inside = min(max(dx, dy), 0.0)
    return outside + inside - radius


def ring(x, y, cx, cy, radius, width):
    """A soft ring: 1 on its centre line, fading to 0 across `width`."""
    d = abs(math.hypot(x - cx, y - cy) - radius)
    return smoothstep(width, 0.0, d)


def band(x, y, cx, cy, radius, width, start, end):
    """A ring cut to an arc, from `start` to `end` radians, measured clockwise from the bottom."""
    a = (math.atan2(y - cy, x - cx) - start) % (2 * math.pi)
    span = (end - start) % (2 * math.pi)
    if a > span:
        return 0.0
    return ring(x, y, cx, cy, radius, width)


def pixels():
    """Every pixel, as bytes: RGBA, row by row, top to bottom."""
    rows = []
    cx = cy = SIZE / 2
    for py in range(SIZE):
        row = bytearray()
        for px in range(SIZE):
            x = px + 0.5
            y = py + 0.5
            # Normalised, so the shapes below are written in a unit square.
            nx = (x - cx) / SIZE
            ny = (y - cy) / SIZE

            # The ground: a vertical gradient, so the icon has a top and a bottom rather than being one flat colour.
            colour = mix(TOP, BOTTOM, py / (SIZE - 1))

            # A soft light from the top left, which is what makes a flat gradient read as a surface.
            glow = smoothstep(0.55, 0.0, math.hypot(nx + 0.28, ny + 0.30))
            colour = mix(colour, (1.0, 1.0, 1.0), glow * 0.12)

            # The nest: a thick arc across the lower half, open at the top, in two tones.
            outer = band(x, y, cx, cy + 0.10 * SIZE, 0.335 * SIZE, 0.085 * SIZE, math.radians(15), math.radians(165))
            if outer > 0:
                colour = over(colour, NEST, outer * 0.95)
            inner = band(x, y, cx, cy + 0.10 * SIZE, 0.335 * SIZE, 0.030 * SIZE, math.radians(30), math.radians(150))
            if inner > 0:
                colour = over(colour, NEST_DARK, inner * 0.85)

            # The game: the square tile a launcher draws, set down in the nest and turned a little.
            angle = math.radians(-8.0)
            rx = nx * math.cos(angle) - ny * math.sin(angle)
            ry = nx * math.sin(angle) + ny * math.cos(angle)
            tile = rounded_box(rx * SIZE, ry * SIZE, SIZE / 2, SIZE / 2 - 0.055 * SIZE, 0.185 * SIZE, 0.055 * SIZE)
            if tile < 0:
                # Its face: lighter at the top, so the tile looks like it is standing rather than painted on.
                face = mix(TILE, TILE_SHADE, clamp((ry + 0.16) / 0.34))
                colour = over(colour, face, 1.0)
                # The game's own mark: a small D-pad, the one thing every game controller has.
                for ax, ay in ((0, -1), (0, 1), (-1, 0), (1, 0)):
                    arm = rounded_box((rx - ax * 0.052) * SIZE, (ry - ay * 0.052) * SIZE,
                                      SIZE / 2, SIZE / 2, 0.020 * SIZE, 0.008 * SIZE)
                    if arm < 0:
                        colour = over(colour, NEST_DARK, 0.92)
                hub = rounded_box(rx * SIZE, ry * SIZE, SIZE / 2, SIZE / 2, 0.017 * SIZE, 0.017 * SIZE)
                if hub < 0:
                    colour = over(colour, NEST_DARK, 0.92)
            elif tile < 2.5:
                # A one-pixel rim, which is what makes the tile sit *in* the nest instead of floating over it.
                colour = over(colour, TILE_SHADE, smoothstep(2.5, 0.0, tile) * 0.55)

            # The two pips: the head's ears, the one shape kept from where the code came from.
            for side in (-1, 1):
                ex = 0.205 * side
                ey = -0.335
                d = math.hypot(nx - ex, (ny - ey) * 1.35)
                pip = smoothstep(0.050, 0.020, d)
                if pip > 0:
                    colour = over(colour, PIP, pip * 0.9)

            row += bytes((
                int(clamp(colour[0]) * 255 + 0.5),
                int(clamp(colour[1]) * 255 + 0.5),
                int(clamp(colour[2]) * 255 + 0.5),
                255,
            ))
        rows.append(bytes(row))
    return rows


def png(rows):
    raw = b"".join(b"\x00" + row for row in rows)     # filter type 0 (none) per scanline

    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    header = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0)   # 8-bit RGBA
    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", header)
            + chunk(b"IDAT", zlib.compress(raw, 9))
            + chunk(b"IEND", b""))


def main():
    data = png(pixels())
    os.makedirs(os.path.dirname(os.path.abspath(OUT)), exist_ok=True)
    with open(OUT, "wb") as handle:
        handle.write(data)
    print(f"wrote {os.path.normpath(OUT)} ({len(data) // 1024} KB)")


if __name__ == "__main__":
    main()

