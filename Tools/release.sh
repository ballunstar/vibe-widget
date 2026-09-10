#!/bin/bash
# Cut a release: build, package the signed app, publish it, point the tap at it.
#
#   Tools/release.sh 1.1.0
#
# This runs here rather than in CI because CI cannot sign. A GitHub runner has
# no certificate and no login keychain, and the widget only loads from a bundle
# signed with a real Team ID — so the machine holding the certificate is the
# machine that has to produce the artefact.
set -euo pipefail
cd "$(dirname "$0")/.."

TAP_REMOTE="${VIBEWIDGET_TAP_REMOTE:-git@github.com:ballunstar/homebrew-tap.git}"

[ $# -eq 1 ] || { echo "usage: Tools/release.sh <version>   e.g. 1.1.0" >&2; exit 2; }
VERSION="${1#v}"
TAG="v${VERSION}"

case "$VERSION" in
  [0-9]*.[0-9]*.[0-9]*) ;;
  *) echo "version should look like 1.2.3, got: $VERSION" >&2; exit 2 ;;
esac

echo "==> checking the working tree"
[ -z "$(git status --porcelain)" ] || { echo "commit or stash your changes first" >&2; exit 1; }
[ "$(git rev-parse --abbrev-ref HEAD)" = "main" ] || { echo "release from main" >&2; exit 1; }
git fetch -q origin main
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || { echo "main and origin/main differ" >&2; exit 1; }
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && { echo "$TAG already exists" >&2; exit 1; }

echo "==> building $VERSION"
# From scratch: an incremental build happily reuses products from an earlier
# single-architecture run, and ships an arm64-only bundle without a word.
rm -rf build
VIBEWIDGET_VERSION="$VERSION" VIBEWIDGET_BUILD="$(date +%s)" \
  ./build.sh --build-only --universal

APP="build/Build/Products/Release/VibeWidget.app"

# A bundle without a Team ID installs and runs, but macOS silently refuses to
# load its widget — which is the whole point of shipping a built app.
TEAM="$(codesign -dv "$APP" 2>&1 | sed -n 's/^TeamIdentifier=\([A-Z0-9][A-Z0-9]*\)$/\1/p')"
[ -n "$TEAM" ] || { echo "built app is not signed with a Team ID — refusing to ship it" >&2; exit 1; }

for binary in "$APP/Contents/MacOS/VibeWidget" \
              "$APP/Contents/PlugIns/VibeWidgetExtension.appex/Contents/MacOS/VibeWidgetExtension"; do
  archs="$(lipo -archs "$binary")"
  case "$archs" in
    *arm64*) ;; *) echo "$binary is missing arm64 ($archs)" >&2; exit 1 ;;
  esac
  case "$archs" in
    *x86_64*) ;; *) echo "$binary is missing x86_64 ($archs)" >&2; exit 1 ;;
  esac
done
echo "==> signed by team $TEAM, universal"

echo "==> packaging"
STAGE="$(mktemp -d)/vibewidget-${VERSION}"
mkdir -p "$STAGE/App" "$STAGE/Widget" "$STAGE/Tools"
# ditto rather than cp: it is the copy that keeps a signed bundle intact.
ditto "$APP" "$STAGE/VibeWidget.app"
ditto Tools/refresh.sh "$STAGE/Tools/refresh.sh"
ditto App/VibeWidget.entitlements "$STAGE/App/VibeWidget.entitlements"
ditto Widget/VibeWidgetExtension.entitlements "$STAGE/Widget/VibeWidgetExtension.entitlements"

ASSET="$PWD/build/vibewidget-${VERSION}-macos.zip"
rm -f "$ASSET"
ditto -c -k --sequesterRsrc --keepParent "$STAGE" "$ASSET"

echo "==> verifying the packaged copy"
CHECK="$(mktemp -d)"
ditto -x -k "$ASSET" "$CHECK"
codesign --verify --strict "$CHECK/vibewidget-${VERSION}/VibeWidget.app"
SHA="$(shasum -a 256 "$ASSET" | cut -d' ' -f1)"
echo "    sha256 $SHA"

echo "==> tagging $TAG"
git tag -a "$TAG" -m "VibeWidget ${VERSION}"
git push -q origin "$TAG"

echo "==> publishing the release"
gh release create "$TAG" "$ASSET" --title "$TAG" --generate-notes

echo "==> pointing the formula at it"
URL="https://github.com/ballunstar/vibe-widget/releases/download/${TAG}/$(basename "$ASSET")"
sed -i '' -e "s|^  url \".*\"|  url \"${URL}\"|" \
          -e "s|^  sha256 \".*\"|  sha256 \"${SHA}\"|" \
          -e "s|^  version \".*\"|  version \"${VERSION}\"|" Formula/vibewidget.rb
git commit -q -am "vibewidget ${VERSION}"
git push -q origin main

echo "==> handing it to the tap"
TAP="$(mktemp -d)/tap"
git clone -q --depth 1 "$TAP_REMOTE" "$TAP"
cp Formula/vibewidget.rb "$TAP/Formula/vibewidget.rb"
git -C "$TAP" add Formula/vibewidget.rb
if git -C "$TAP" diff --cached --quiet; then
  echo "    tap already serves ${VERSION}"
else
  git -C "$TAP" commit -q -m "vibewidget ${VERSION}"
  git -C "$TAP" push -q
fi

echo
echo "released ${TAG}. Users get it with:"
echo "    brew upgrade vibewidget && vibewidget-refresh"
