#!/usr/bin/env bash
# 把 repo 根目錄的 icon.svg 輸出成 icon-1024.png（1024×1024，不透明）。
# 這台 Windows 沒有 SVG 轉檔工具，借 Edge 的無頭模式開一頁只放這張圖再截圖。
# 用法（Git Bash，在 repo 根目錄）：bash ios/tools/render-icon.sh && python ios/tools/make-icons.py
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
tmp="$(mktemp -d)"
cp "$root/icon.svg" "$tmp/icon.svg"
printf '<!doctype html><html><body style="margin:0"><img src="icon.svg" width="1024" height="1024" style="display:block"></body></html>' > "$tmp/icon.html"
edge="/c/Program Files (x86)/Microsoft/Edge/Application/msedge.exe"
"$edge" --headless=new --disable-gpu --hide-scrollbars --no-first-run \
  --user-data-dir="$(cygpath -w "$tmp/profile")" --force-device-scale-factor=1 --window-size=1024,1024 \
  --screenshot="$(cygpath -w "$tmp")\shot.png" "file:///$(cygpath -m "$tmp/icon.html")"
python -c "from PIL import Image; Image.open(r'$(cygpath -w "$tmp")\shot.png').convert('RGB').save(r'$(cygpath -w "$root")\icon-1024.png')"
rm -rf "$tmp"
echo "[render-icon] 寫好了 icon-1024.png" >&2
