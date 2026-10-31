"""Generates the tiling PBR detail textures in assets/textures/ (CC0, made here).

Each material is two images:
  <name>_detail.png : RGB = colour detail around mid grey (the shader multiplies
                      its base colour by 2 * detail), A = roughness
  <name>_normal.png : tangent-space normal map (OpenGL convention, +Y up)
All images tile seamlessly (noise is built in the frequency domain, shapes
wrap around the edges). Run:  python3 tools/gen_textures.py
"""
import os
import numpy as np
from PIL import Image

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "textures")
rng = np.random.default_rng(20261031)


def noise(n, beta, seed=None):
    """Periodic 1/f^beta noise in 0..1."""
    r = np.random.default_rng(seed) if seed is not None else rng
    white = r.standard_normal((n, n))
    f = np.fft.fftfreq(n)
    fx, fy = np.meshgrid(f, f)
    k = np.sqrt(fx * fx + fy * fy)
    k[0, 0] = 1.0
    spec = np.fft.fft2(white) / k ** beta
    spec[0, 0] = 0.0
    out = np.real(np.fft.ifft2(spec))
    out -= out.min()
    return out / max(out.max(), 1e-9)


def blur(a, passes=1):
    for _ in range(passes):
        a = (a + np.roll(a, 1, 0) + np.roll(a, -1, 0) + np.roll(a, 1, 1) + np.roll(a, -1, 1)) / 5.0
    return a


def normal_from_height(h, strength):
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5 * strength
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5 * strength
    nz = np.ones_like(h)
    length = np.sqrt(dx * dx + dy * dy + nz * nz)
    nx, ny, nz = -dx / length, dy / length, nz / length
    return np.stack([nx * 0.5 + 0.5, ny * 0.5 + 0.5, nz * 0.5 + 0.5], axis=-1)


def splat(h, n, count, rmin, rmax, value, seed):
    """Wrapped round blobs (stones, pores) added to a height field."""
    r = np.random.default_rng(seed)
    ys, xs = np.mgrid[0:n, 0:n]
    for _ in range(count):
        cx, cy = r.uniform(0, n, 2)
        rad = r.uniform(rmin, rmax)
        x0, x1 = int(cx - rad - 1), int(cx + rad + 2)
        y0, y1 = int(cy - rad - 1), int(cy + rad + 2)
        yy, xx = np.mgrid[y0:y1, x0:x1]
        d = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2) / rad
        v = np.clip(1.0 - d, 0.0, 1.0) ** 0.6 * value * r.uniform(0.6, 1.0)
        h[yy % n, xx % n] += v
    return h


def crack_mask(n, count, seed, width=1.2):
    r = np.random.default_rng(seed)
    m = np.zeros((n, n))
    for _ in range(count):
        x, y = r.uniform(0, n, 2)
        ang = r.uniform(0, np.pi * 2)
        for _ in range(int(r.uniform(n * 0.15, n * 0.5))):
            ang += r.normal(0, 0.25)
            x += np.cos(ang)
            y += np.sin(ang)
            ix, iy = int(x) % n, int(y) % n
            m[iy, ix] = 1.0
            if width > 1.0:
                m[(iy + 1) % n, ix] = 0.6
                m[iy, (ix + 1) % n] = 0.6
    return np.clip(blur(m, 1) * 2.0, 0, 1)


def save(name, rgb, alpha=None):
    rgb = np.clip(rgb, 0, 1)
    if alpha is not None:
        img = np.concatenate([rgb, np.clip(alpha, 0, 1)[..., None]], axis=-1)
        Image.fromarray((img * 255 + 0.5).astype(np.uint8), "RGBA").save(os.path.join(OUT, name), optimize=True)
    else:
        Image.fromarray((rgb * 255 + 0.5).astype(np.uint8), "RGB").save(os.path.join(OUT, name), optimize=True)
    print("wrote", name)


def grey_detail(v, tint=(1.0, 1.0, 1.0)):
    """Detail colour around 0.5 (multiplied by 2 in the shader)."""
    v = 0.5 + (v - v.mean())
    return np.stack([v * tint[0], v * tint[1], v * tint[2]], axis=-1)


def asphalt():
    n = 1024
    h = noise(n, 1.6, 1) * 0.5
    fine = noise(n, 0.4, 2)
    h = splat(h, n, 9000, 1.0, 2.6, 0.55, 3)         # aggregate stones
    cracks = crack_mask(n, 7, 4)
    h -= cracks * 0.9
    tone = 0.5 + (noise(n, 1.8, 5) - 0.5) * 0.18 + (fine - 0.5) * 0.12
    stones = np.clip(splat(np.zeros((n, n)), n, 3500, 0.8, 1.8, 1.0, 6), 0, 1)
    tone += stones * 0.16 - cracks * 0.28
    rough = 0.86 - stones * 0.18 + cracks * 0.1 + (fine - 0.5) * 0.06
    save("asphalt_detail.png", grey_detail(tone, (1.0, 1.0, 1.02)), rough)
    save("asphalt_normal.png", normal_from_height(blur(h, 1), 6.0))


def concrete():
    n = 512
    base = noise(n, 1.4, 11)
    fine = noise(n, 0.3, 12)
    pores = np.clip(splat(np.zeros((n, n)), n, 2500, 0.6, 1.4, 1.0, 13), 0, 1)
    stains = np.clip((noise(n, 2.2, 14) - 0.55) * 3.0, 0, 1)
    tone = 0.5 + (base - 0.5) * 0.14 + (fine - 0.5) * 0.08 - pores * 0.12 - stains * 0.1
    rough = 0.88 + pores * 0.06 - stains * 0.05
    h = base * 0.4 + fine * 0.15 - pores * 0.6
    save("concrete_detail.png", grey_detail(tone), rough)
    save("concrete_normal.png", normal_from_height(blur(h, 1), 3.0))


def plaster():
    n = 512
    base = noise(n, 1.7, 21)
    fine = noise(n, 0.5, 22)
    streaks = noise(n, 1.2, 23)
    # Vertical rain streaks: stretch noise along y by averaging rows.
    for _ in range(24):
        streaks = (streaks + np.roll(streaks, 1, 0) + np.roll(streaks, -1, 0)) / 3.0
    streaks = np.clip((streaks - 0.5) * 4.0, 0, 1)
    tone = 0.5 + (base - 0.5) * 0.12 + (fine - 0.5) * 0.1 - streaks * 0.12
    rough = 0.9 - streaks * 0.06
    save("plaster_detail.png", grey_detail(tone), rough)
    save("plaster_normal.png", normal_from_height(blur(fine * 0.6 + base * 0.4, 1), 2.5))


def brick():
    """Running bond, 8 courses x 4 bricks per tile (tile = 1.0 x 0.6 m in the shader)."""
    n = 512
    rows, cols = 8, 4
    ys, xs = np.mgrid[0:n, 0:n]
    rh = n / rows
    cw = n / cols
    row = (ys // rh).astype(int)
    offset = np.where(row % 2 == 1, cw * 0.5, 0.0)
    bx = (xs + offset) % n
    col = (bx // cw).astype(int)
    fy = (ys % rh) / rh
    fx = (bx % cw) / cw
    mortar_y = np.minimum(fy, 1 - fy) * rh
    mortar_x = np.minimum(fx, 1 - fx) * cw
    mortar = np.clip(1.5 - np.minimum(mortar_x, mortar_y) / 2.2, 0, 1)
    r = np.random.default_rng(31)
    shade = r.uniform(-0.12, 0.12, (rows, cols * 2))
    brick_tone = shade[row % rows, col % (cols * 2)]
    fine = noise(n, 0.6, 32)
    tone = 0.5 + brick_tone + (fine - 0.5) * 0.12
    tone = tone * (1 - mortar) + (0.62 + (fine - 0.5) * 0.05) * mortar
    rough = 0.82 + mortar * 0.1
    # Bricks read reddish when multiplied with the wall colour.
    rgb = grey_detail(tone)
    rgb[..., 0] += (1 - mortar) * 0.06
    rgb[..., 2] -= (1 - mortar) * 0.05
    h = (1 - mortar) * 0.8 + fine * 0.2
    save("brick_detail.png", rgb, rough)
    save("brick_normal.png", normal_from_height(blur(h, 1), 5.0))


def roof_tiles():
    """Clay tile rows: 8 rows, scalloped edges."""
    n = 512
    rows = 8
    ys, xs = np.mgrid[0:n, 0:n]
    rh = n / rows
    row = (ys // rh).astype(int)
    fy = (ys % rh) / rh
    cols = 10
    cw = n / cols
    offset = np.where(row % 2 == 1, cw * 0.5, 0.0)
    fx = ((xs + offset) % cw) / cw
    curve = np.sin(fx * np.pi)            # rounded tile profile across
    h = curve * 0.6 + fy * 0.4            # each row overlaps the next
    edge = np.clip((fy - 0.9) * 10, 0, 1)
    fine = noise(n, 0.7, 41)
    r = np.random.default_rng(42)
    shade = r.uniform(-0.1, 0.1, (rows, cols * 2))
    tone = 0.5 + shade[row % rows, ((xs + offset) // cw).astype(int) % (cols * 2)] + (fine - 0.5) * 0.1 - edge * 0.2
    rough = 0.78 + edge * 0.1
    save("rooftile_detail.png", grey_detail(tone), rough)
    save("rooftile_normal.png", normal_from_height(blur(h - edge * 0.5, 1), 4.0))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    asphalt()
    concrete()
    plaster()
    brick()
    roof_tiles()
