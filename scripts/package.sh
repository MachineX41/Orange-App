#!/bin/zsh
# Builds a release Orange.app and wraps it as build/dist/Orange.dmg and build/dist/Orange.zip.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

"$root/scripts/build-app.sh"

app="$root/build/Orange.app"
dist="$root/build/dist"
stage="$root/build/dmg"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"

rm -rf "$dist" "$stage"
mkdir -p "$dist" "$stage"

ditto -c -k --keepParent "$app" "$dist/Orange.zip"

cp -R "$app" "$stage/"
ln -s /Applications "$stage/Applications"
hdiutil create -volname "Orange $version" -srcfolder "$stage" -fs HFS+ -format UDZO -ov "$dist/Orange.dmg" >/dev/null
rm -rf "$stage"

(cd "$dist" && shasum -a 256 Orange.dmg Orange.zip > SHA256SUMS.txt)

echo "Orange $version"
cat "$dist/SHA256SUMS.txt"
