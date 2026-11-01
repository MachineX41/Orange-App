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
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Helpers" "$root/build/AppIcon.iconset"

helper="$root/build/ocr-runtime/OrangeOCRHelper"
if [[ -x "$helper" ]]; then
  cp "$helper" "$app/Contents/Helpers/OrangeOCRHelper"
  # Sign the helper before the enclosing app so nested code is sealed first.
  codesign --force --sign - --identifier app.orange.studio.helper "$app/Contents/Helpers/OrangeOCRHelper" >/dev/null
fi

cp "$bin/Orange" "$app/Contents/MacOS/Orange"
cp "$root/Configuration/Info.plist" "$app/Contents/Info.plist"
cp "$root/Configuration/AppIcon.png" "$app/Contents/Resources/OrangeLogo.png"
cp "$root/THIRD_PARTY_NOTICES.md" "$app/Contents/Resources/"
for lproj in "$root"/Configuration/*.lproj; do
  cp -R "$lproj" "$app/Contents/Resources/"
done
xcrun actool "$root/Configuration/Assets.xcassets" --compile "$app/Contents/Resources" \
  --platform macosx --minimum-deployment-target 26.0 --accent-color AccentColor \
  --output-partial-info-plist "$root/build/assets-info.plist" >/dev/null
chmod +x "$app/Contents/MacOS/Orange"

swiftc -O -framework AppKit -framework CoreGraphics \
  "$root/scripts/RenderIcon.swift" -o "$root/build/render-icon"
"$root/build/render-icon" "$root/build/AppIcon.iconset" "$root/Configuration/AppIcon.png"
iconutil -c icns "$root/build/AppIcon.iconset" -o "$app/Contents/Resources/AppIcon.icns"
# Ad-hoc signatures default to a hash-based requirement, so macOS would forget folder permissions after every update.
codesign --force --deep --sign - --identifier app.orange.studio \
  --requirements '=designated => identifier "app.orange.studio"' "$app" >/dev/null

echo "Built $app"
