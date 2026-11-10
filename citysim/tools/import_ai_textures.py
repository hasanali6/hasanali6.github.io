"""Turns AI-generated surface photos into the game's tiling PBR textures.

Sources (generated with Higgsfield "z_image", kept as JPEG in
assets/textures/source/, which Godot ignores):
  brick.jpg plaster.jpg rooftile.jpg asphalt.jpg concrete.jpg grass.jpg sand.jpg

For each one this writes, in assets/textures/:
  <name>_detail.png : RGB = colour detail around mid grey (shaders multiply
                      their base colour by 2 * detail), A = roughness
  <name>_normal.png : tangent-space normal map (OpenGL convention)
(grass: detail only; the terrain and lawns multiply it in up close).

Steps: crop -> make seamless (the overlap whose two strips match best is
found first, so brick courses and tile rows line up; then a minimum-error
cut through the overlap hides the join) -> flatten large light gradients
(they would show up as a repeating pattern) -> detail / roughness / normal.

Run:  python3 tools/import_ai_textures.py
"""
import os

import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.join(os.path.dirname(__file__), "..")
SRC = os.path.join(ROOT, "assets", "textures", "source")
OUT = os.path.join(ROOT, "assets", "textures")

# name: crop (left, top, right, bottom as fractions), output size, overlap
# search range (fractions of the side), chroma kept in the detail (0 = grey),
# detail contrast, normal strength, roughness (base, variation).
MATERIALS = {
    # Brick and roof tiles use a small part of the photo (about 7 courses /
    # rows): the shaders draw them larger than life so they read on a phone.
    "brick": {"crop": (0.1, 0.1, 0.56, 0.52), "size": 512, "overlap": (0.05, 0.16), "chroma": 0.45,
              "contrast": 0.9, "normal": 5.0, "rough": (0.84, 0.14), "height": "saturation", "tint": (1.1, 1.0, 0.91)},
    "plaster": {"feather": 40.0, "crop": (0.05, 0.05, 0.95, 0.95), "size": 512, "overlap": (0.1, 0.2), "chroma": 0.0,
                "contrast": 6.5, "normal": 3.0, "rough": (0.88, 0.08)},
    "rooftile": {"crop": (0.14, 0.2, 0.64, 0.62), "size": 512, "overlap": (0.05, 0.16), "chroma": 0.3,
                 "contrast": 0.8, "normal": 5.5, "rough": (0.8, 0.14)},
    "asphalt": {"feather": 40.0, "crop": (0.05, 0.05, 0.95, 0.95), "size": 1024, "overlap": (0.1, 0.2), "chroma": 0.0,
                "contrast": 0.6, "normal": 6.0, "rough": (0.9, 0.08)},
    "concrete": {"crop": (0.02, 0.02, 0.98, 0.98), "size": 512, "overlap": (0.06, 0.2), "chroma": 0.1,
                 "contrast": 1.0, "normal": 3.5, "rough": (0.86, 0.1)},
    "sand": {"feather": 40.0, "crop": (0.05, 0.05, 0.95, 0.95), "size": 512, "overlap": (0.12, 0.2), "chroma": 0.6,
             "contrast": 0.9, "normal": 3.0, "rough": (0.92, 0.05)},
    "grass": {"feather": 40.0, "crop": (0.05, 0.05, 0.95, 0.95), "size": 512, "overlap": (0.12, 0.2), "chroma": 1.0,
              "contrast": 0.5, "normal": 3.0, "rough": (0.92, 0.05)},
}


def load(name, crop):
    img = Image.open(os.path.join(SRC, name + ".jpg")).convert("RGB")
    w, h = img.size
    box = (int(w * crop[0]), int(h * crop[1]), int(w * crop[2]), int(h * crop[3]))
    return np.asarray(img.crop(box), dtype=np.float32) / 255.0


def best_overlap(a, lo, hi):
    """Overlap width (columns) whose left and right strips match best."""
    w = a.shape[1]
    grey = a.mean(axis=2)
    best, best_err = int(w * lo), np.inf
    for o in range(int(w * lo), int(w * hi)):
        err = np.mean((grey[:, :o] - grey[:, w - o:]) ** 2)
        if err < best_err:
            best, best_err = o, err
    return best


def wrap_columns(a, lo, hi, feather):
    """Returns a narrower image that tiles left-right: the first columns
    are taken from the right end up to a minimum-error cut, so the join with
    the last column is the photo's own continuation."""
    w = a.shape[1]
    o = best_overlap(a, lo, hi)
    left = a[:, :o]
    right = a[:, w - o:]
    err = ((left - right) ** 2).sum(axis=2)
    # Blur the error a little so the cut prefers broad agreement.
    err = (err + np.roll(err, 1, 0) + np.roll(err, -1, 0)) / 3.0
    h = err.shape[0]
    cost = err.copy()
    for y in range(1, h):
        prev = cost[y - 1]
        best = np.minimum(prev, np.minimum(np.roll(prev, 1), np.roll(prev, -1)))
        best[0] = min(prev[0], prev[1])
        best[-1] = min(prev[-1], prev[-2])
        cost[y] += best
    seam = np.zeros(h, dtype=int)
    seam[-1] = int(np.argmin(cost[-1]))
    for y in range(h - 2, -1, -1):
        x = seam[y + 1]
        x0, x1 = max(x - 1, 0), min(x + 2, o)
        seam[y] = x0 + int(np.argmin(cost[y, x0:x1]))
    # Left of the cut: the right strip (continues the last column); a short
    # feather hides what little difference is left.
    xs = np.arange(o)[None, :]
    mask = np.clip((xs - seam[:, None]) / feather + 0.5, 0.0, 1.0)[..., None]
    out = a[:, :w - o].copy()
    out[:, :o] = right * (1.0 - mask) + left * mask
    return out


def seamless(a, lo, hi, feather):
    a = wrap_columns(a, lo, hi, feather)
    a = np.transpose(wrap_columns(np.transpose(a, (1, 0, 2)), lo, hi, feather), (1, 0, 2))
    return a


def resize(a, size):
    img = Image.fromarray((np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB")
    return np.asarray(img.resize((size, size), Image.LANCZOS), dtype=np.float32) / 255.0


def wrap_blur(a, radius, mode="wrap"):
    """Gaussian blur that wraps around the edges (keeps tiling intact)."""
    pad = int(radius * 3)
    padded = np.pad(a, ((pad, pad), (pad, pad)) + ((0, 0),) * (a.ndim - 2), mode=mode)
    if a.ndim == 2:
        img = Image.fromarray((np.clip(padded, 0, 1) * 255).astype(np.uint8), "L")
    else:
        img = Image.fromarray((np.clip(padded, 0, 1) * 255).astype(np.uint8), "RGB")
    out = np.asarray(img.filter(ImageFilter.GaussianBlur(radius)), dtype=np.float32) / 255.0
    return out[pad:-pad, pad:-pad]


def flatten(a, radius, mode="wrap"):
    """Removes slow brightness and colour drift (keeps the mean colour)."""
    low = wrap_blur(a, radius, mode)
    mean = a.reshape(-1, 3).mean(axis=0)
    return np.clip(a - low + mean, 0.0, 1.0)


def normal_from_height(h, strength):
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5 * strength
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5 * strength
    nz = np.ones_like(h)
    length = np.sqrt(dx * dx + dy * dy + nz * nz)
    return np.stack([-dx / length * 0.5 + 0.5, dy / length * 0.5 + 0.5, nz / length * 0.5 + 0.5], axis=-1)


def save(name, rgb, alpha=None):
    rgb = np.clip(rgb, 0, 1)
    if alpha is not None:
        img = np.concatenate([rgb, np.clip(alpha, 0, 1)[..., None]], axis=-1)
        Image.fromarray((img * 255 + 0.5).astype(np.uint8), "RGBA").save(os.path.join(OUT, name), optimize=True)
    else:
        Image.fromarray((rgb * 255 + 0.5).astype(np.uint8), "RGB").save(os.path.join(OUT, name), optimize=True)
    print("wrote", name)


def convert(name, m):
    a = load(name, m["crop"])
    # Even out the photo's lighting first, so the two sides of the join
    # have the same brightness; once more after, wrapping, for what is left.
    a = flatten(a, a.shape[0] * 0.12, "reflect")
    a = seamless(a, m["overlap"][0], m["overlap"][1], m.get("feather", 6.0))
    a = resize(a, m["size"])
    a = flatten(a, m["size"] * 0.18)
    mean = a.reshape(-1, 3).mean(axis=0)
    lum = a @ np.array([0.299, 0.587, 0.114], dtype=np.float32)
    lum_mean = float(lum.mean())
    # Detail: brightness relative to the mean, plus part of the colour shift.
    grey = (lum / lum_mean)[..., None]
    ratio = a / mean[None, None, :]
    rel = grey * (1.0 - m["chroma"]) + ratio * m["chroma"]
    detail = 0.5 + (rel - 1.0) * 0.5 * m["contrast"]
    # Brick keeps a warm cast, as walls multiply it with their paint colour.
    detail = detail * np.array(m.get("tint", (1.0, 1.0, 1.0)), dtype=np.float32)[None, None, :]
    # Height: bright = raised (joints, gaps and cracks are darker).
    if m.get("height") == "saturation":
        # Brick: the grey mortar is the low part, whatever its brightness.
        height = wrap_blur(a.max(axis=2) - a.min(axis=2), 1.2)
    else:
        height = wrap_blur(lum, 1.2)
    height = (height - height.min()) / max(float(height.max() - height.min()), 1e-6)
    base, var = m["rough"]
    rough = base + (0.5 - height) * var
    save(name + "_detail.png", detail, rough)
    # Grass and sand are only used as colour detail (the ground keeps its own normal map).
    if name not in ("grass", "sand"):
        save(name + "_normal.png", normal_from_height(height, m["normal"] * m["size"] / 512.0))
    return a


def main():
    sheet = []
    for name, m in MATERIALS.items():
        a = convert(name, m)
        # 2 x 2 tiling preview to check the seams by eye.
        t = np.tile(resize(a, 256), (2, 2, 1))
        sheet.append(t)
    preview = np.concatenate(sheet, axis=1)
    path = os.environ.get("TEXTURE_PREVIEW")
    if path:
        Image.fromarray((preview * 255 + 0.5).astype(np.uint8), "RGB").save(path, quality=88)
        print("preview", path)


if __name__ == "__main__":
    main()
