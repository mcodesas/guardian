"""Generate native/store/web brand icons from the approved Guardian master.
Run from any directory: python scripts/generate_brand_icons.py [--apply]
Requires Pillow. No image downloads, no changes to manifests unrelated to branding.
"""
import argparse
import json
import shutil
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "branding" / "guardian-logo.webp"
OUT = ROOT / "branding" / "generated"
FLUTTER = ROOT / "apps" / "guardian_flutter"
WEB = ROOT / "apps" / "guardian_web"

def save(img, path, size):
    path.parent.mkdir(parents=True, exist_ok=True)
    img.resize((size, size), Image.Resampling.LANCZOS).save(path, format="PNG", optimize=True)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="Copy icons into existing Flutter runners and public website.")
    args = parser.parse_args()
    master = Image.open(SOURCE).convert("RGB")
    if master.width != master.height or master.width < 1024:
        raise ValueError("Expected square master at least 1024 px")
    # A generous safe zone for adaptive masks; preserve complete approved mark.
    padded = Image.new("RGB", master.size, master.getpixel((0, 0)))
    inner = master.resize((int(master.width * .74), int(master.height * .74)), Image.Resampling.LANCZOS)
    padded.paste(inner, ((master.width-inner.width)//2, (master.height-inner.height)//2))
    android = OUT / "android"
    ios = OUT / "ios" / "AppIcon.appiconset"
    web = OUT / "web"
    save(master, android / "google-play-512.png", 512)
    for density, size in {"mdpi":48,"hdpi":72,"xhdpi":96,"xxhdpi":144,"xxxhdpi":192}.items():
        res = android / "res" / ("mipmap-" + density)
        save(master, res / "ic_launcher.png", size)
        save(master, res / "ic_launcher_round.png", size)
        save(padded, res / "ic_guardian_adaptive.png", int(size * 2.25))
    xml = android / "res" / "mipmap-anydpi-v26" / "ic_launcher.xml"
    xml.parent.mkdir(parents=True, exist_ok=True)
    xml.write_text('<?xml version="1.0" encoding="utf-8"?>\n<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android"><background android:drawable="@android:color/black"/><foreground android:drawable="@mipmap/ic_guardian_adaptive"/></adaptive-icon>\n', encoding="utf-8")
    shutil.copyfile(xml, xml.with_name("ic_launcher_round.xml"))
    save(master, ios / "AppIcon-1024.png", 1024)
    (ios / "Contents.json").write_text(json.dumps({"images":[{"filename":"AppIcon-1024.png","idiom":"universal","platform":"ios","size":"1024x1024"}],"info":{"author":"xcode","version":1}}, indent=2)+"\n")
    for size in [16,32,48,64]:
        save(master, web / f"favicon-{size}.png", size)
    master.save(web / "favicon.ico", sizes=[(16,16),(32,32),(48,48),(64,64)])
    save(master, web / "apple-touch-icon.png", 180)
    for size in [192,512]:
        save(master, web / "icons" / f"Icon-{size}.png", size)
        save(padded, web / "icons" / f"Icon-maskable-{size}.png", size)
    for size in [256,512]:
        save(master, web / f"guardian-logo-{size}.png", size)
    manifest = {"name":"Guardian","short_name":"Guardian","start_url":"./","display":"standalone","background_color":"#06101f","theme_color":"#06101f","icons":[{"src":f"icons/Icon-{prefix}{size}.png","sizes":f"{size}x{size}","type":"image/png","purpose":purpose} for prefix,purpose in [("","any"),("maskable-","maskable")] for size in [192,512]]}
    (web / "manifest.webmanifest").write_text(json.dumps(manifest, indent=2)+"\n")
    for path in OUT.rglob("*.png"):
        with Image.open(path) as im:
            im.verify()
    if args.apply:
        res = FLUTTER / "android" / "app" / "src" / "main" / "res"
        if res.is_dir():
            shutil.copytree(android / "res", res, dirs_exist_ok=True)
        target = FLUTTER / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
        if target.is_dir():
            shutil.copytree(ios, target, dirs_exist_ok=True)
        windows = FLUTTER / "windows" / "runner" / "resources"
        if windows.is_dir():
            master.save(windows / "app_icon.ico", sizes=[(16,16),(32,32),(48,48),(64,64),(128,128),(256,256)])
        shutil.copytree(web, WEB, dirs_exist_ok=True)
        flutter_web = FLUTTER / "web"
        if flutter_web.is_dir():
            shutil.copytree(web / "icons", flutter_web / "icons", dirs_exist_ok=True)
            shutil.copyfile(web / "favicon-32.png", flutter_web / "favicon.png")
    print("Guardian icon assets generated:", len(list(OUT.rglob("*.png"))), "PNG files")

if __name__ == "__main__":
    main()
