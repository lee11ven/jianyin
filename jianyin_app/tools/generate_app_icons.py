"""Generate Android launcher icons with transparent background from source PNG."""
from __future__ import annotations

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = Path(
    r"C:\Users\Administrator\.cursor\projects\d-works-ai-sign-language-to-speech-conversion\assets\c__Users_Administrator_AppData_Roaming_Cursor_User_workspaceStorage_3b8a32cdde130b44f131499dfd7f9a73_images_____OK____-ece89cc4-e316-4425-ad74-7aad3e7028b2.png"
)
RES = ROOT / "android" / "app" / "src" / "main" / "res"
BRANDING = ROOT / "assets" / "branding"

MIPMAP_SIZES = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}

FOREGROUND_SIZES = {
    "drawable-mdpi": 108,
    "drawable-hdpi": 162,
    "drawable-xhdpi": 216,
    "drawable-xxhdpi": 324,
    "drawable-xxxhdpi": 432,
}


def remove_black_background(im: Image.Image) -> Image.Image:
    im = im.convert("RGBA")
    px = im.load()
    w, h = im.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            m = max(r, g, b)
            if m <= 18:
                px[x, y] = (r, g, b, 0)
            elif m <= 55 and max(r, g, b) - min(r, g, b) < 25:
                # Dark neutral pixels (anti-aliased edge on black)
                t = (m - 18) / (55 - 18)
                px[x, y] = (r, g, b, int(a * t))
    return im


def fit_square(im: Image.Image, size: int, padding_ratio: float = 0.08) -> Image.Image:
    bbox = im.getbbox()
    if not bbox:
        return Image.new("RGBA", (size, size), (0, 0, 0, 0))
    cropped = im.crop(bbox)
    pad = int(size * padding_ratio)
    inner = size - 2 * pad
    cw, ch = cropped.size
    scale = min(inner / cw, inner / ch)
    nw, nh = max(1, int(cw * scale)), max(1, int(ch * scale))
    resized = cropped.resize((nw, nh), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ox = (size - nw) // 2
    oy = (size - nh) // 2
    canvas.paste(resized, (ox, oy), resized)
    return canvas


def save_png(path: Path, im: Image.Image) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    im.save(path, format="PNG", optimize=True)


def main() -> None:
    src = Image.open(SOURCE)
    transparent = remove_black_background(src)

    BRANDING.mkdir(parents=True, exist_ok=True)
    master = fit_square(transparent, 1024, padding_ratio=0.06)
    save_png(BRANDING / "app_icon.png", master)

    for folder, px in MIPMAP_SIZES.items():
        save_png(RES / folder / "ic_launcher.png", fit_square(transparent, px))

    for folder, px in FOREGROUND_SIZES.items():
        save_png(RES / folder / "ic_launcher_foreground.png", fit_square(transparent, px))

    print("Generated icons under res/ and assets/branding/app_icon.png")


if __name__ == "__main__":
    main()
