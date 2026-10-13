"""Render the app icon and splash artwork into app/assets/branding/.

  python tool/make_brand_assets.py      (needs Pillow; training/.venv has it)

Then: dart run flutter_launcher_icons && dart run flutter_native_splash:create
The glyph is a banknote with sound waves: money, spoken aloud.
"""

from pathlib import Path

from PIL import Image, ImageDraw

BG = (11, 12, 15, 255)          # canvas, dark theme (theme.dart)
LIME = (198, 242, 78, 255)      # default accent (settings.dart)
SIZE = 1024
SS = 4                          # supersampling for smooth edges
OUT = Path(__file__).resolve().parent.parent / "assets" / "branding"


def glyph(draw: ImageDraw.ImageDraw, cx: float, cy: float, s: float) -> None:
    """Draw the glyph centred on (cx, cy); s = overall width in px."""
    w, h = s * 0.62, s * 0.42
    x0, y0 = cx - s * 0.5, cy - h / 2
    r = h * 0.16
    # Note body, with a dark medallion and two corner pips like a real note.
    draw.rounded_rectangle([x0, y0, x0 + w, y0 + h], radius=r, fill=LIME)
    m = h * 0.25
    draw.ellipse([x0 + w / 2 - m, cy - m, x0 + w / 2 + m, cy + m], fill=BG)
    p = h * 0.075
    for px, py in ((x0 + h * 0.2, y0 + h * 0.2), (x0 + w - h * 0.2, y0 + h - h * 0.2)):
        draw.ellipse([px - p, py - p, px + p, py + p], fill=BG)
    # Sound waves to the right.
    stroke = s * 0.055
    ax = x0 + w + s * 0.02
    for i, rad in enumerate((s * 0.14, s * 0.27)):
        box = [ax - rad, cy - rad, ax + rad, cy + rad]
        draw.arc(box, start=-48, end=48, fill=LIME, width=round(stroke))
        # Round caps on the arc ends.
        import math
        for ang in (-48, 48):
            ex = ax + (rad - stroke / 2) * math.cos(math.radians(ang))
            ey = cy + (rad - stroke / 2) * math.sin(math.radians(ang))
            draw.ellipse([ex - stroke / 2, ey - stroke / 2, ex + stroke / 2, ey + stroke / 2], fill=LIME)


def render(background: bool, scale: float) -> Image.Image:
    big = SIZE * SS
    img = Image.new("RGBA", (big, big), BG if background else (0, 0, 0, 0))
    glyph(ImageDraw.Draw(img), big * 0.5 + big * scale * 0.05, big * 0.5, big * scale)
    return img.resize((SIZE, SIZE), Image.LANCZOS)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    render(True, 0.70).save(OUT / "icon.png")              # legacy + iOS icon, full bleed
    render(False, 0.52).save(OUT / "icon_foreground.png")  # adaptive icon: stay inside the 66% safe zone
    render(False, 0.50).save(OUT / "splash.png")           # Android 12 splash crops to a circle
    print("wrote", *sorted(p.name for p in OUT.iterdir()))


if __name__ == "__main__":
    main()
