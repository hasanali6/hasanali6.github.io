"""Turns the AI front elevations of the school and the hospital into the
textures drawn on those buildings' street faces.

Sources (made with Higgsfield "z_image", kept in assets/textures/source/,
which Godot ignores):
  school_facade.jpg    two-storey red brick school with an "OKUL" sign
  hospital_facade.jpg  white hospital with a red cross and "HASTANE"

Outputs (assets/textures/):
  facade_school.png    1024 x 512, the facade cropped edge to edge (RGB)
  facade_hospital.png  1024 x 1024, RGBA: the sky around the raised middle
                       block is cut out (alpha 0) so it shows as a step

The hospital art came with two flaws that are painted over here: a double
cross (it now gets a proper single red cross) and the word HASTANE written
twice (the smaller copy on the canopy is removed).

Run:  python3 tools/make_facades.py
"""
import os

from PIL import Image, ImageDraw

ROOT = os.path.join(os.path.dirname(__file__), "..")
SRC = os.path.join(ROOT, "assets", "textures", "source")
OUT = os.path.join(ROOT, "assets", "textures")

# Pixel boxes in the 2048-px sources.
SCHOOL_CROP = (0, 88, 2010, 1062)
HOSPITAL_CROP = (24, 100, 2044, 1890)
HOSPITAL_BODY = (24, 230, 2044, 1890)     # main block below its roof line
HOSPITAL_TOWER = (724, 100, 1204, 230)    # raised middle block with the cross
CROSS_PATCH = (836, 176, 1114, 514)       # the double cross and its shadow
CROSS_CENTRE = (967, 338)
TEXT_PATCH = (794, 1428, 1132, 1500)      # the second, smaller HASTANE
RED = (222, 66, 52)


def fill_between(img: Image.Image, box: tuple) -> None:
    """Repaints box row by row, blending the pixels just left and right of it."""
    x0, y0, x1, y1 = box
    px = img.load()
    for y in range(y0, y1):
        a = px[x0 - 2, y]
        b = px[x1 + 2, y]
        for x in range(x0, x1):
            t = (x - x0) / max(x1 - x0 - 1, 1)
            px[x, y] = tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def school() -> None:
    img = Image.open(os.path.join(SRC, "school_facade.jpg")).convert("RGB")
    img = img.crop(SCHOOL_CROP).resize((1024, 512), Image.LANCZOS)
    img.save(os.path.join(OUT, "facade_school.png"), optimize=True)


def hospital() -> None:
    img = Image.open(os.path.join(SRC, "hospital_facade.jpg")).convert("RGB")
    fill_between(img, CROSS_PATCH)
    fill_between(img, TEXT_PATCH)
    d = ImageDraw.Draw(img)
    cx, cy = CROSS_CENTRE
    arm, half = 128, 42
    # A soft offset shadow first, then the cross itself.
    for dx, dy, col in [(10, 12, (196, 198, 198)), (0, 0, RED)]:
        d.rectangle([cx - half + dx, cy - arm + dy, cx + half + dx, cy + arm + dy], fill=col)
        d.rectangle([cx - arm + dx, cy - half + dy, cx + arm + dx, cy + half + dy], fill=col)
    rgba = img.convert("RGBA")
    mask = Image.new("L", img.size, 0)
    md = ImageDraw.Draw(mask)
    md.rectangle(HOSPITAL_BODY, fill=255)
    md.rectangle(HOSPITAL_TOWER, fill=255)
    rgba.putalpha(mask)
    rgba = rgba.crop(HOSPITAL_CROP).resize((1024, 1024), Image.LANCZOS)
    rgba.save(os.path.join(OUT, "facade_hospital.png"), optimize=True)


if __name__ == "__main__":
    school()
    hospital()
    print("wrote facade_school.png and facade_hospital.png")
