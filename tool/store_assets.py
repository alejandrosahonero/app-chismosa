"""Builds the Google Play listing images from the golden screenshots.

    flutter test tool/screenshots/screenshots_test.dart --update-goldens
    python tool/store_assets.py

Writes to build/store/ (git-ignored): 1080x1920 phone/tablet captures with a
headline, and the 1024x500 feature graphic. Play wants 9:16, the goldens are
1080x2340, so each one is scaled into a framed phone under its headline.
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
GOLDENS = ROOT / "tool/screenshots/goldens"
OUT = ROOT / "build/store"
FONTS = ROOT / "assets/fonts"

MAROON = (0x4A, 0x00, 0x00)
BONE = (0xF4, 0xEF, 0xEA)
DUST = (0xC9, 0xA9, 0xA0)

SHOTS = [
    ("3_deck_light.png", "Chismes reales,", "contados en anónimo"),
    ("2_welcome_gestures.png", "Desliza, opina", "y comparte"),
    ("4_deck_dark.png", "Del mundo o", "de tu país"),
    ("5_my_stories.png", "Cuenta el tuyo:", "nadie sabrá que fuiste tú"),
    ("1_welcome.png", "Sin email", "ni contraseña"),
]


def font(name: str, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(FONTS / name), size)


def rounded(img: Image.Image, radius: int) -> Image.Image:
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, *img.size), radius, fill=255)
    out = Image.new("RGBA", img.size)
    out.paste(img, mask=mask)
    return out


def capture(src: str, line1: str, line2: str, index: int) -> None:
    canvas = Image.new("RGB", (1080, 1920), MAROON)
    draw = ImageDraw.Draw(canvas)
    title = font("BricolageGrotesque-ExtraBold.ttf", 88)
    sub = font("Onest-SemiBold.ttf", 56)
    draw.text((540, 150), line1, font=title, fill=BONE, anchor="mm")
    draw.text((540, 250), line2, font=sub, fill=DUST, anchor="mm")

    shot = Image.open(GOLDENS / src).convert("RGB")
    height = 1920 - 360 - 60
    width = round(shot.width * height / shot.height)
    shot = shot.resize((width, height), Image.LANCZOS)
    frame = Image.new("RGB", (width + 24, height + 24), BONE)
    frame = rounded(frame, 56)
    canvas.paste(frame, ((1080 - frame.width) // 2, 348), frame)
    canvas.paste(rounded(shot, 44), ((1080 - width) // 2, 360), rounded(shot, 44))
    canvas.save(OUT / f"phone_{index}.png", optimize=True)


def feature_graphic() -> None:
    canvas = Image.new("RGB", (1024, 500), MAROON)
    draw = ImageDraw.Draw(canvas)
    icon = Image.open(ROOT / "brand/icon_preview_1024.png").convert("RGBA").resize((260, 260), Image.LANCZOS)
    canvas.paste(rounded(icon, 58), (84, 120), rounded(icon, 58))
    draw.text((400, 190), "Chismosa", font=font("BricolageGrotesque-ExtraBold.ttf", 104), fill=BONE, anchor="lm")
    draw.text((404, 300), "Todo el mundo tiene un chisme.", font=font("Onest-SemiBold.ttf", 38), fill=DUST, anchor="lm")
    canvas.save(OUT / "feature_graphic.png", optimize=True)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for i, (src, a, b) in enumerate(SHOTS, start=1):
        capture(src, a, b, i)
    feature_graphic()
    (OUT / "icon_512.png").write_bytes((ROOT / "brand/play_store_icon_512.png").read_bytes())
    for f in sorted(OUT.iterdir()):
        print(f.name, Image.open(f).size, f.stat().st_size // 1024, "KB")


if __name__ == "__main__":
    main()
