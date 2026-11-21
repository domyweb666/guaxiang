# 從 repo 根目錄的 icon-512.png 做出 App 圖示（1024、不透明）和設定頁頁尾用的 Logo。
# 用法：python ios/tools/make-icons.py
# 1024 是從 512 放大的，邊緣會糊一點；上架前請用 icon.svg 重新輸出一張 1024 換掉。
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
big = src.resize((1024, 1024), Image.LANCZOS)
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
