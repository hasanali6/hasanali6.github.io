"""Bakes the map's water distance into assets/textures/water_sdf.png.

The terrain and water shaders need, for every pixel, the signed distance to
the nearest river bank, lake shore or sea shore (negative = in the water).
Working it out per pixel means testing every river segment, which is the
most expensive part of the ground shader on phones. The water never moves,
so it is baked once here, with the same maths as MapWater (river smoothed
with Catmull-Rom, elliptic lakes, wavy coastline), and the shaders read one
texel instead.

Texture: 8-bit grey, SIZE x SIZE covering EXTENT metres centred on the map
origin; value = clamp(distance, -RANGE, RANGE) mapped to 0..255. Run again
whenever data/map.json "water" changes:  python3 tools/gen_water_sdf.py
"""
import json
import math
import os

import numpy as np
from PIL import Image

ROOT = os.path.join(os.path.dirname(__file__), "..")
SIZE = 2048
EXTENT = 8192.0     # metres covered (the playable map is 4000 m)
RANGE = 64.0        # distances beyond this are clamped (shaders only use the near band)


def catmull_rom(ctrl, subdiv):
    out = []
    n = len(ctrl)
    for i in range(n - 1):
        p0 = ctrl[max(i - 1, 0)]
        p1 = ctrl[i]
        p2 = ctrl[i + 1]
        p3 = ctrl[min(i + 2, n - 1)]
        for s in range(subdiv):
            t = s / subdiv
            t2 = t * t
            t3 = t2 * t
            out.append(0.5 * ((2 * p1) + (p2 - p0) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (3 * p1 - p0 - 3 * p2 + p3) * t3))
    out.append(ctrl[-1])
    return np.array(out)


def main():
    cfg = json.load(open(os.path.join(ROOT, "data", "map.json")))["water"]
    ctrl = [np.array(p, dtype=np.float64) for p in cfg["river_points"]]
    river = catmull_rom(ctrl, int(cfg["river_subdivisions"]))
    half = float(cfg["river_width_m"]) * 0.5
    lakes = cfg["lakes"]
    coast = cfg.get("coast")

    px = (np.arange(SIZE) + 0.5) / SIZE * EXTENT - EXTENT * 0.5
    out = np.empty((SIZE, SIZE), dtype=np.float32)
    for r0 in range(0, SIZE, 128):
        ys = px[r0:r0 + 128]
        X, Y = np.meshgrid(px, ys)
        d = np.full(X.shape, np.inf)
        for i in range(len(river) - 1):
            a = river[i]
            b = river[i + 1]
            ab = b - a
            l2 = ab @ ab
            t = np.clip(((X - a[0]) * ab[0] + (Y - a[1]) * ab[1]) / max(l2, 1e-9), 0.0, 1.0)
            dx = X - (a[0] + ab[0] * t)
            dy = Y - (a[1] + ab[1] * t)
            d = np.minimum(d, np.sqrt(dx * dx + dy * dy))
        d -= half
        for cx, cy, rx, ry in lakes:
            rel = np.sqrt(((X - cx) / rx) ** 2 + ((Y - cy) / ry) ** 2)
            d = np.minimum(d, (rel - 1.0) * min(rx, ry))
        if coast:
            z = np.full(X.shape, float(coast["z"]))
            slope = np.zeros(X.shape)
            for amp, wl, ph in coast.get("waves", [])[:2]:
                a = X * 2.0 * math.pi / wl + ph
                z += amp * np.sin(a)
                slope += amp * 2.0 * math.pi / wl * np.cos(a)
            d = np.minimum(d, (z - Y) / np.sqrt(1.0 + slope * slope))
        out[r0:r0 + 128] = d
    v = np.clip(out, -RANGE, RANGE) / (2.0 * RANGE) + 0.5
    img = Image.fromarray(np.round(v * 255.0).astype(np.uint8), "L")
    path = os.path.join(ROOT, "assets", "textures", "water_sdf.png")
    img.save(path, optimize=True)
    print("wrote", path, img.size, "%.1f m/px" % (EXTENT / SIZE))


if __name__ == "__main__":
    main()
