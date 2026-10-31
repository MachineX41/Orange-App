#!/bin/zsh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

config="release"
if [[ "${1:-}" == "--debug" ]]; then
  config="debug"
fi

swift build -c "$config" --product Orange
bin="$(swift build -c "$config" --show-bin-path)"

app="$root/build/Orange.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$root/build/AppIcon.iconset"

cp "$bin/Orange" "$app/Contents/MacOS/Orange"
cp "$root/Configuration/Info.plist" "$app/Contents/Info.plist"
cp "$root/Configuration/AppIcon.png" "$app/Contents/Resources/OrangeLogo.png"
chmod +x "$app/Contents/MacOS/Orange"

swiftc -O -framework AppKit -framework CoreGraphics \
  "$root/scripts/RenderIcon.swift" -o "$root/build/render-icon"
"$root/build/render-icon" "$root/build/AppIcon.iconset" "$root/Configuration/AppIcon.png"
iconutil -c icns "$root/build/AppIcon.iconset" -o "$app/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$app" >/dev/null

echo "Built $app"
