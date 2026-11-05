"""Builds the game's icons, logo and splash from two source images.

Sources (made with Higgsfield, kept in assets/branding/source/):
  icon_source.png   square 3D city artwork (no text)
  title_source.png  wide 3D city scene with open sky at the top (no text)

Outputs:
  icon.png                                      project / desktop icon (512)
  assets/branding/icon_192.png                  Android launcher icon
  assets/branding/icon_fg_432.png               Android adaptive foreground
  assets/branding/icon_bg_432.png               Android adaptive background
  assets/branding/logo.png                      "ŞEHİR SİM" 3D title (transparent)
  assets/branding/splash.png                    boot splash: scene + title

The title is set here in the game's own font (Nunito, heaviest weight), so
the Turkish letters are always right. Run: python3 tools/make_branding.py
"""
import os
import sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.join(os.path.dirname(__file__), "..")
SRC = os.path.join(ROOT, "assets", "branding", "source")
OUT = os.path.join(ROOT, "assets", "branding")
FONT = os.path.join(ROOT, "assets", "ui", "fonts", "Nunito-Variable.ttf")
TITLE = "ŞEHİR SİM"


def rounded(img: Image.Image, radius_frac: float) -> Image.Image:
    """Square image with rounded corners (alpha)."""
    w, h = img.size
    mask = Image.new("L", (w * 4, h * 4), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, w * 4 - 1, h * 4 - 1], radius=int(w * 4 * radius_frac), fill=255)
    mask = mask.resize((w, h), Image.LANCZOS)
    out = img.convert("RGBA")
    out.putalpha(mask)
    return out


def square_crop(img: Image.Image) -> Image.Image:
    w, h = img.size
    s = min(w, h)
    return img.crop(((w - s) // 2, (h - s) // 2, (w - s) // 2 + s, (h - s) // 2 + s))


def font(size: int) -> ImageFont.FreeTypeFont:
    f = ImageFont.truetype(FONT, size)
    try:
        f.set_variation_by_axes([1000])
    except Exception:
        pass
    return f


def title_art(width: int) -> Image.Image:
    """Chunky 3D title: navy extrusion, orange-gold face, white outline."""
    size = int(width * 0.16)
    f = font(size)
    pad = int(size * 0.5)
    probe = ImageDraw.Draw(Image.new("RGBA", (10, 10)))
    x0, y0, x1, y1 = probe.textbbox((0, 0), TITLE, font=f, stroke_width=int(size * 0.07))
    tw, th = x1 - x0, y1 - y0
    depth = int(size * 0.11)
    W, H = tw + pad * 2, th + pad * 2 + depth
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ox, oy = pad - x0, pad - y0
    stroke = int(size * 0.07)
    # Soft drop shadow.
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).text((ox + depth * 0.6, oy + depth * 1.6), TITLE, font=f, fill=(10, 20, 40, 150),
                                stroke_width=stroke, stroke_fill=(10, 20, 40, 150))
    img = Image.alpha_composite(img, shadow.filter(ImageFilter.GaussianBlur(size * 0.06)))
    d = ImageDraw.Draw(img)
    # Extrusion: stacked dark layers going down.
    for k in range(depth, 0, -1):
        t = k / depth
        col = (int(20 + 25 * (1 - t)), int(38 + 30 * (1 - t)), int(80 + 40 * (1 - t)), 255)
        d.text((ox, oy + k), TITLE, font=f, fill=col, stroke_width=stroke, stroke_fill=col)
    # White outline, then the gradient face.
    d.text((ox, oy), TITLE, font=f, fill=(255, 255, 255, 255), stroke_width=stroke, stroke_fill=(255, 255, 255, 255))
    face_mask = Image.new("L", (W, H), 0)
    ImageDraw.Draw(face_mask).text((ox, oy), TITLE, font=f, fill=255)
    grad = Image.new("RGBA", (W, H))
    gd = ImageDraw.Draw(grad)
    top, bottom = (255, 214, 70), (247, 120, 24)
    for y in range(H):
        t = min(max((y - oy) / max(th, 1), 0.0), 1.0)
        gd.line([(0, y), (W, y)], fill=tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)) + (255,))
    img.paste(grad, (0, 0), face_mask)
    # Glossy highlight on the upper half of the letters.
    gloss_mask = Image.new("L", (W, H), 0)
    ImageDraw.Draw(gloss_mask).text((ox, oy), TITLE, font=f, fill=90)
    cut = Image.new("L", (W, H), 0)
    ImageDraw.Draw(cut).rectangle([0, 0, W, oy + th * 0.42], fill=255)
    gloss_mask = Image.composite(gloss_mask, Image.new("L", (W, H), 0), cut)
    img.paste(Image.new("RGBA", (W, H), (255, 255, 255, 255)), (0, 0), gloss_mask)
    return img


def main() -> None:
    icon_src = Image.open(os.path.join(SRC, "icon_source.png")).convert("RGB")
    title_src = Image.open(os.path.join(SRC, "title_source.png")).convert("RGB")
    os.makedirs(OUT, exist_ok=True)

    sq = square_crop(icon_src)
    rounded(sq.resize((512, 512), Image.LANCZOS), 0.22).save(os.path.join(ROOT, "icon.png"))
    rounded(sq.resize((192, 192), Image.LANCZOS), 0.22).save(os.path.join(OUT, "icon_192.png"))
    # Adaptive icon: launchers cut the layers to a circle or squircle and
    # only promise the middle two thirds, so the city is scaled into that
    # safe zone over a blurred, enlarged copy of its own sky. The foreground
    # is left clear.
    # The sky behind: a gradient between the art's own corner colours, so
    # the scaled art blends in without a visible frame.
    small = sq.resize((64, 64), Image.LANCZOS)
    c0 = small.getpixel((2, 2))
    c1 = small.getpixel((61, 61))
    bg = Image.new("RGB", (432, 432))
    px = bg.load()
    for y in range(432):
        for x in range(432):
            t = (x + y) / 862.0
            px[x, y] = tuple(int(c0[i] + (c1[i] - c0[i]) * t) for i in range(3))
    art = sq.resize((318, 318), Image.LANCZOS)
    feather = Image.new("L", (318, 318), 0)
    ImageDraw.Draw(feather).rounded_rectangle([18, 18, 299, 299], radius=50, fill=255)
    feather = feather.filter(ImageFilter.GaussianBlur(14))
    bg.paste(art, (57, 57), feather)
    bg.save(os.path.join(OUT, "icon_bg_432.png"))
    Image.new("RGBA", (432, 432), (0, 0, 0, 0)).save(os.path.join(OUT, "icon_fg_432.png"))

    # Splash: the scene, the title over the open sky.
    W, H = 1920, 1080
    w, h = title_src.size
    scale = max(W / w, H / h)
    scene = title_src.resize((int(w * scale + 0.5), int(h * scale + 0.5)), Image.LANCZOS)
    scene = scene.crop(((scene.width - W) // 2, (scene.height - H) // 2, (scene.width - W) // 2 + W, (scene.height - H) // 2 + H))
    logo = title_art(W)
    lw = int(W * 0.62)
    logo_s = logo.resize((lw, int(logo.height * lw / logo.width)), Image.LANCZOS)
    logo_s.save(os.path.join(OUT, "logo.png"))
    splash = scene.convert("RGBA")
    splash.alpha_composite(logo_s, ((W - lw) // 2, int(H * 0.06)))
    splash.convert("RGB").save(os.path.join(OUT, "splash.png"), optimize=True)
    print("wrote icon.png and", ", ".join(sorted(os.listdir(OUT))))


if __name__ == "__main__":
    sys.exit(main())
