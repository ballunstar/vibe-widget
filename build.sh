#!/bin/bash
# Regenerate the Xcode project, build Release, install, and restart the app.
set -euo pipefail
cd "$(dirname "$0")"

# Homebrew passes both: it installs the bundle itself, and it cannot sign —
# see the comment on UNSIGNED in generate_project.py.
BUILD_ONLY=""
NO_ICON=""
for arg in "$@"; do
  case "$arg" in
    --build-only) BUILD_ONLY=1 ;;
    --unsigned)   export VIBEWIDGET_UNSIGNED=1 ;;
    --no-icon)    NO_ICON=1 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

# App/AppIcon.icns is committed, so a build never has to render it. Homebrew
# passes --no-icon because it puts its own compiler shims ahead of swiftc in
# PATH, and the renderer never survives that.
if [ -n "$NO_ICON" ]; then
  [ -f App/AppIcon.icns ] || { echo "--no-icon, but App/AppIcon.icns is missing" >&2; exit 1; }
else
  echo "==> rendering app icon"
  ICONSET="$(mktemp -d)/AppIcon.iconset"
  mkdir -p "$ICONSET"
  MAKEICON="$(mktemp -d)/makeicon"
  swiftc -O -o "$MAKEICON" Tools/MakeIcon.swift
  for pair in "16:icon_16x16" "32:icon_16x16@2x" "32:icon_32x32" "64:icon_32x32@2x" \
              "128:icon_128x128" "256:icon_128x128@2x" "256:icon_256x256" \
              "512:icon_256x256@2x" "512:icon_512x512" "1024:icon_512x512@2x"; do
    "$MAKEICON" "${pair%%:*}" "$ICONSET/${pair##*:}.png"
  done
  iconutil -c icns "$ICONSET" -o App/AppIcon.icns
fi

echo "==> generating project"
python3 generate_project.py

echo "==> building"
# grep would mask a failing xcodebuild, and Homebrew must not install a broken
# bundle, so the verdict comes from the log rather than from the exit status.
LOG="$(mktemp -t vibewidget-build)"
set +o pipefail
xcodebuild -project VibeWidget.xcodeproj -scheme VibeWidget \
  -configuration Release -derivedDataPath build build 2>&1 \
  | tee "$LOG" | grep -E "error:|warning:|BUILD" || true
set -o pipefail
if ! grep -q "BUILD SUCCEEDED" "$LOG"; then
  echo "build failed — full log at $LOG" >&2
  exit 1
fi

if [ -n "$BUILD_ONLY" ]; then
  echo "==> built build/Build/Products/Release/VibeWidget.app"
  exit 0
fi

exec Tools/refresh.sh build/Build/Products/Release/VibeWidget.app
