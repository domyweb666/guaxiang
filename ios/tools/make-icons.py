# 從 repo 根目錄的圖示做出 App 圖示（1024、不透明）和設定頁頁尾用的 Logo。
# 用法：python ios/tools/make-icons.py
# App 圖示優先用 icon-1024.png（從 icon.svg 直接輸出，2026-11-26 用 Edge 無頭模式截的，見 ios/tools/render-icon.sh）；
# 沒有才退回把 icon-512.png 放大，邊緣會糊一點。
import json
import os
import sys

from PIL import Image

here = os.path.dirname(os.path.abspath(__file__))
root = os.path.abspath(os.path.join(here, "..", ".."))
assets = os.path.join(root, "ios", "Guaxiang", "Resources", "Assets.xcassets")

src = Image.open(os.path.join(root, "icon-512.png")).convert("RGBA")
print("來源", src.size, "左上角顏色", src.getpixel((2, 2)))


def write(folder, name, contents):
    os.makedirs(folder, exist_ok=True)
    with open(os.path.join(folder, name), "w", encoding="utf-8", newline="\n") as f:
        json.dump(contents, f, ensure_ascii=False, indent=2)
        f.write("\n")


write(assets, "Contents.json", {"info": {"author": "xcode", "version": 1}})

# App 圖示：鋪滿、不能有透明。角落透明的話用圖示正中上方的顏色補
sharp = os.path.join(root, "icon-1024.png")
big = Image.open(sharp).convert("RGBA") if os.path.exists(sharp) else src.resize((1024, 1024), Image.LANCZOS)
print("App 圖示來源", "icon-1024.png" if os.path.exists(sharp) else "icon-512.png 放大")
fill = src.getpixel((256, 40))[:3] if src.getpixel((2, 2))[3] < 255 else src.getpixel((2, 2))[:3]
flat = Image.new("RGB", (1024, 1024), fill)
flat.paste(big, (0, 0), big)
icon_dir = os.path.join(assets, "AppIcon.appiconset")
os.makedirs(icon_dir, exist_ok=True)
flat.save(os.path.join(icon_dir, "icon-1024.png"))
write(icon_dir, "Contents.json", {
    "images": [{"filename": "icon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
    "info": {"author": "xcode", "version": 1},
})

logo_dir = os.path.join(assets, "Logo.imageset")
os.makedirs(logo_dir, exist_ok=True)
src.resize((192, 192), Image.LANCZOS).save(os.path.join(logo_dir, "logo.png"))
write(logo_dir, "Contents.json", {
    "images": [{"filename": "logo.png", "idiom": "universal"}],
    "info": {"author": "xcode", "version": 1},
})
print("寫好了", assets, "補底色", fill)
sys.exit(0)
