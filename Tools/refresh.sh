#!/bin/bash
# Sign VibeWidget.app with your own certificate, install it, and make macOS
# pick up the new widget.
#
# Signing happens here rather than during the build because Homebrew forks its
# builds with setsid(2), which leaves the user's security session behind: the
# login keychain is unreachable there, so codesign has no identity and there is
# no certificate to read a Team ID from. This script runs in your own shell,
# where both are available.
#
# Re-registering matters just as much: the widget gallery serves the extension
# from a LaunchServices record, so an upgraded .appex keeps running the old code
# until something re-registers the app.
set -euo pipefail

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
IDENTITY="${VIBEWIDGET_IDENTITY:-Apple Development}"

# $0 is usually a Homebrew symlink into the Cellar; both the bundle and the
# entitlement templates sit next to the real bin/.
here="$(python3 -c 'import os,sys; print(os.path.dirname(os.path.realpath(sys.argv[1])))' "$0")"
root="$here/.."

SOURCE="${1:-$root/VibeWidget.app}"
DEST_DIR="${2:-$HOME/Applications}"
DEST="$DEST_DIR/VibeWidget.app"

APP_ENTITLEMENTS="$root/App/VibeWidget.entitlements"
WIDGET_ENTITLEMENTS="$root/Widget/VibeWidgetExtension.entitlements"

for path in "$SOURCE" "$APP_ENTITLEMENTS" "$WIDGET_ENTITLEMENTS"; do
  [ -e "$path" ] || { echo "missing: $path" >&2; exit 1; }
done

# The Team ID is the certificate's OU, not the identifier inside its name.
TEAM="${VIBEWIDGET_TEAM:-}"
if [ -z "$TEAM" ]; then
  TEAM="$(security find-certificate -c "$IDENTITY" -p 2>/dev/null \
          | openssl x509 -noout -subject 2>/dev/null \
          | tr ',' '\n' | sed -n 's/.*OU *= *\([A-Z0-9][A-Z0-9]*\).*/\1/p' | head -1)"
fi
if [ -z "$TEAM" ]; then
  cat >&2 <<'EOF'
No "Apple Development" certificate in your login keychain.

Create one — a free Apple ID is enough, no paid membership needed:

  1. Open Xcode > Settings... > Accounts
  2. Add your Apple ID, select it, click "Manage Certificates..."
  3. Click + and choose "Apple Development"

Then run vibewidget-refresh again.
EOF
  exit 1
fi

# macOS only lets an App Group be shared by bundles signed with the Team ID the
# group is prefixed with, so the identifier is only knowable once the signing
# certificate is: it goes into the entitlements and into both Info.plists here.
GROUP="$TEAM.group.com.phonpreecha.vibewidget"
echo "==> signing as team $TEAM"

echo "==> stopping the running app"
# Copying over a running bundle leaves a mix of old and new Mach-O files.
pkill -f "VibeWidget.app" 2>/dev/null || true
sleep 1

echo "==> installing to $DEST"
case "$DEST" in */VibeWidget.app) ;; *) echo "refusing to replace $DEST" >&2; exit 1 ;; esac
mkdir -p "$DEST_DIR"
rm -rf "$DEST"
ditto "$SOURCE" "$DEST"

APPEX="$DEST/Contents/PlugIns/VibeWidgetExtension.appex"
[ -d "$APPEX" ] || { echo "no widget extension inside $DEST" >&2; exit 1; }

for plist in "$DEST/Contents/Info.plist" "$APPEX/Contents/Info.plist"; do
  plutil -replace AppGroupIdentifier -string "$GROUP" "$plist"
done

ENTITLEMENTS="$(mktemp -d)"
sed 's|[$](APP_GROUP_IDENTIFIER)|'"$GROUP"'|' "$APP_ENTITLEMENTS" > "$ENTITLEMENTS/app.plist"
sed 's|[$](APP_GROUP_IDENTIFIER)|'"$GROUP"'|' "$WIDGET_ENTITLEMENTS" > "$ENTITLEMENTS/widget.plist"

# Inner bundle first: the app's signature covers the extension it embeds.
codesign --force --timestamp=none --sign "$IDENTITY" \
  --entitlements "$ENTITLEMENTS/widget.plist" "$APPEX"
codesign --force --timestamp=none --sign "$IDENTITY" \
  --entitlements "$ENTITLEMENTS/app.plist" "$DEST"
codesign --verify --strict "$DEST"

echo "==> registering the widget extension"
"$LSREGISTER" -f "$DEST"

echo "==> launching"
open "$DEST"
sleep 3

echo "==> widget extension registration:"
pluginkit -mAvvv 2>/dev/null | grep -A1 -i vibe || echo "    NOT REGISTERED"
