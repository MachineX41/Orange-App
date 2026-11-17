#!/bin/zsh
# Publishes Orange for Windows and Linux. Does not upload a GitHub Release.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
dotnet test
dist="$root/dist"
rm -rf "$dist"
mkdir -p "$dist"
dotnet publish src/Orange.App/Orange.App.csproj -c Release -r win-x64 --self-contained true -o "$dist/win"
dotnet publish src/Orange.App/Orange.App.csproj -c Release -r linux-x64 --self-contained true -o "$dist/linux"
fetch_ffmpeg() {
  local dest="$1" url="$2" kind="$3"
  local tmp
  tmp="$(mktemp -d)"
  curl -fL --retry 2 -o "$tmp/ffmpeg.pkg" "$url"
  if [ "$kind" = "zip" ]; then
    unzip -q "$tmp/ffmpeg.pkg" -d "$tmp/out"
  else
    mkdir -p "$tmp/out"
    tar -xJf "$tmp/ffmpeg.pkg" -C "$tmp/out"
  fi
  find "$tmp/out" -type f \( -name 'ffmpeg' -o -name 'ffmpeg.exe' \) -exec cp {} "$dest/" \;
  chmod +x "$dest"/ffmpeg "$dest"/ffprobe "$dest"/ffplay 2>/dev/null || true
  rm -rf "$tmp"
}
fetch_ffmpeg "$dist/win" "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip" zip
fetch_ffmpeg "$dist/linux" "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-linux64-gpl.tar.xz" tar
mkdir -p "$dist/win/models" "$dist/linux/models"
curl -fsSL -o "$dist/win/models/haarcascade_frontalface_default.xml" https://raw.githubusercontent.com/opencv/opencv/4.10.0/data/haarcascades/haarcascade_frontalface_default.xml
cp "$dist/win/models/haarcascade_frontalface_default.xml" "$dist/linux/models/"
(cd "$dist" && ditto -c -k --keepParent win Orange-windows-x64.zip)
mkdir -p "$dist/Orange.AppDir/usr/bin"
cp -R "$dist/linux/." "$dist/Orange.AppDir/usr/bin/"
cat > "$dist/Orange.AppDir/AppRun" <<'EOF'
#!/bin/sh
HERE="$(dirname "$(readlink -f "$0")")"
exec "$HERE/usr/bin/Orange" "$@"
EOF
chmod -R a+rX "$dist/Orange.AppDir"
cp "$root/../Configuration/AppIcon.png" "$dist/Orange.AppDir/orange.png"
cat > "$dist/Orange.AppDir/orange.desktop" <<'EOF'
[Desktop Entry]
Name=Orange
Exec=Orange
Icon=orange
Type=Application
Categories=Utility;
EOF
if command -v appimagetool >/dev/null 2>&1; then
  ARCH=x86_64 appimagetool "$dist/Orange.AppDir" "$dist/Orange-linux-x64.AppImage"
else
  tar -C "$dist" -czf "$dist/Orange-linux-x64.tar.gz" Orange.AppDir
fi
echo "Packages are in $dist"
