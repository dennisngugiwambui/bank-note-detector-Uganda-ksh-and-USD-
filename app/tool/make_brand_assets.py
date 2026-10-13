"""Render the NoteLens icon, splash and wordmark into app/assets/branding/.

  python tool/make_brand_assets.py      (needs Pillow + numpy; training/.venv has both)

Then: dart run flutter_launcher_icons && dart run flutter_native_splash:create

The mark is a lens: a ring with an angular lime -> mint -> cyan gradient and a
soft glow, framing a small banknote with a glint. Background is a deep
green-black radial gradient.
"""

from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

SIZE = 1024
OUT = Path(__file__).resolve().parent.parent / "assets" / "branding"
FONT = Path(__file__).resolve().parent.parent / "assets" / "fonts" / "Inter-ExtraBold.ttf"

BG_CENTER = (18, 34, 27)
BG_EDGE = (5, 8, 7)
STOPS = [(198, 242, 78), (62, 230, 176), (34, 211, 238), (198, 242, 78)]  # lime, mint, cyan, lime


def radial_bg(size: int) -> Image.Image:
    y, x = np.mgrid[0:size, 0:size].astype(np.float32)
    d = np.sqrt((x - size * 0.42) ** 2 + (y - size * 0.35) ** 2) / (size * 0.85)
    d = np.clip(d, 0, 1)[..., None]
    rgb = np.array(BG_CENTER) * (1 - d) + np.array(BG_EDGE) * d
    return Image.fromarray(rgb.astype(np.uint8), "RGB").convert("RGBA")


def angular(size: int) -> Image.Image:
    y, x = np.mgrid[0:size, 0:size].astype(np.float32)
    a = (np.arctan2(y - size / 2, x - size / 2) / (2 * np.pi) + 0.5 + 0.375) % 1.0
    seg = a * (len(STOPS) - 1)
    i = np.floor(seg).astype(int).clip(0, len(STOPS) - 2)
    f = (seg - i)[..., None]
    stops = np.array(STOPS, dtype=np.float32)
    rgb = stops[i] * (1 - f) + stops[i + 1] * f
    return Image.fromarray(rgb.astype(np.uint8), "RGB").convert("RGBA")


def mark(size: int, scale: float, mono: bool = False) -> Image.Image:
    """Transparent RGBA with the lens mark centred, ring outer diameter = size*scale."""
    ss = 4
    big = size * ss
    c = big / 2
    r_out = big * scale / 2
    ring_w = r_out * 0.2

    ring_mask = Image.new("L", (big, big), 0)
    d = ImageDraw.Draw(ring_mask)
    d.ellipse([c - r_out, c - r_out, c + r_out, c + r_out], fill=255)
    d.ellipse([c - r_out + ring_w, c - r_out + ring_w, c + r_out - ring_w, c + r_out - ring_w], fill=0)

    # Banknote inside the lens, slightly tilted, with a medallion.
    note = Image.new("L", (big, big), 0)
    nd = ImageDraw.Draw(note)
    nw, nh = r_out * 1.02, r_out * 0.62
    nd.rounded_rectangle([c - nw / 2, c - nh / 2, c + nw / 2, c + nh / 2], radius=nh * 0.18, fill=255)
    m = nh * 0.24
    nd.ellipse([c - m, c - m, c + m, c + m], fill=0)
    p = nh * 0.075
    for px, py in ((c - nw / 2 + nh * 0.2, c - nh / 2 + nh * 0.22), (c + nw / 2 - nh * 0.2, c + nh / 2 - nh * 0.22)):
        nd.ellipse([px - p, py - p, px + p, py + p], fill=0)
    note = note.rotate(-12, resample=Image.BICUBIC, center=(c, c))

    fill = Image.new("RGBA", (big, big), (255, 255, 255, 255)) if mono else angular(big)
    out = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    if not mono:
        glow = Image.new("RGBA", (big, big), (0, 0, 0, 0))
        glow.paste(fill, (0, 0), ring_mask)
        glow = glow.filter(ImageFilter.GaussianBlur(big * 0.035))
        glow.putalpha(glow.getchannel("A").point(lambda v: int(v * 0.75)))
        out = Image.alpha_composite(out, glow)
    ring = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    ring.paste(fill, (0, 0), ring_mask)
    out = Image.alpha_composite(out, ring)
    note_fill = Image.new("RGBA", (big, big), (255, 255, 255, 255) if mono else (236, 255, 214, 255))
    note_layer = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    note_layer.paste(note_fill, (0, 0), note)
    out = Image.alpha_composite(out, note_layer)

    if not mono:
        # Glint: a short white arc on the ring, top-left, like light on glass.
        glint = Image.new("L", (big, big), 0)
        gd = ImageDraw.Draw(glint)
        rr = r_out - ring_w / 2
        gd.arc([c - rr, c - rr, c + rr, c + rr], start=200, end=235, fill=255, width=int(ring_w * 0.32))
        glint = glint.filter(ImageFilter.GaussianBlur(ring_w * 0.06))
        white = Image.new("RGBA", (big, big), (255, 255, 255, 230))
        gl = Image.new("RGBA", (big, big), (0, 0, 0, 0))
        gl.paste(white, (0, 0), glint)
        out = Image.alpha_composite(out, gl)
    return out.resize((size, size), Image.LANCZOS)


def wordmark(height: int = 220) -> Image.Image:
    font = ImageFont.truetype(str(FONT), int(height * 0.62))
    parts = [("Note", (255, 255, 255, 255)), ("Lens", (198, 242, 78, 255))]
    widths = [font.getbbox(t)[2] - font.getbbox(t)[0] for t, _ in parts]
    w = sum(widths) + int(height * 0.1)
    img = Image.new("RGBA", (w, height), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    x = int(height * 0.05)
    for (t, col), tw in zip(parts, widths):
        d.text((x - font.getbbox(t)[0], height * 0.14), t, font=font, fill=col)
        x += tw
    return img


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    icon = radial_bg(SIZE)
    icon = Image.alpha_composite(icon, mark(SIZE, 0.66))
    icon.convert("RGB").save(OUT / "icon.png")                     # legacy + iOS (full bleed)
    mark(SIZE, 0.50).save(OUT / "icon_foreground.png")              # adaptive: inside the 66% safe zone
    mark(SIZE, 0.50, mono=True).save(OUT / "icon_monochrome.png")   # Android 13 themed icons
    mark(SIZE, 0.46).save(OUT / "splash.png")                       # Android 12 crops the splash icon to a circle
    mark(512, 0.92).save(OUT / "logo.png")                          # in-app logo
    wordmark().save(OUT / "wordmark.png")                           # splash branding + in-app
    radial_bg(512).convert("RGB").save(OUT / "adaptive_background.png")
    print("wrote", *sorted(p.name for p in OUT.iterdir()))


if __name__ == "__main__":
    main()
