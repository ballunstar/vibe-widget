#!/bin/bash
# Install VibeWidget.app and make macOS pick up the widget it carries.
#
#   vibewidget-refresh            install the bundle as it was signed
#   vibewidget-refresh --sign     re-sign it with your own certificate first
#
# Copying alone is not enough: the widget gallery serves the extension from a
# LaunchServices record, so an upgraded .appex keeps running the old code until
# the app is re-registered. Homebrew cannot do this itself — it is not allowed
# to write to $HOME — which is why this is a separate command.
#
# --sign exists because macOS ties an App Group to the Team ID that signed the
# bundle. Releases arrive already signed, so it is normally unnecessary; it is
# the repair for a bundle built with --unsigned, or one whose signature this
# Mac will not honour.
set -euo pipefail

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
IDENTITY="${VIBEWIDGET_IDENTITY:-Apple Development}"

SIGN=""
SOURCE_ARG=""
DEST_ARG=""
for arg in "$@"; do
  case "$arg" in
    --sign) SIGN=1 ;;
    -*) echo "unknown option: $arg" >&2; exit 2 ;;
    *) if [ -z "$SOURCE_ARG" ]; then SOURCE_ARG="$arg"; else DEST_ARG="$arg"; fi ;;
  esac
done

# $0 is usually a Homebrew symlink into the Cellar; the bundle and the
# entitlement templates sit next to the real bin/.
here="$(python3 -c 'import os,sys; print(os.path.dirname(os.path.realpath(sys.argv[1])))' "$0")"
root="$here/.."

SOURCE="${SOURCE_ARG:-$root/VibeWidget.app}"
DEST_DIR="${DEST_ARG:-$HOME/Applications}"
DEST="$DEST_DIR/VibeWidget.app"

[ -d "$SOURCE" ] || { echo "no app bundle at $SOURCE" >&2; exit 1; }

echo "==> stopping the running app"
# Copying over a running bundle leaves a mix of old and new Mach-O files.
pkill -x VibeWidget 2>/dev/null || true
sleep 1

SOURCE_VERSION="$(plutil -extract CFBundleShortVersionString raw -o - \
  "$SOURCE/Contents/Info.plist" 2>/dev/null || echo "?")"

echo "==> installing $SOURCE_VERSION to $DEST"
case "$DEST" in */VibeWidget.app) ;; *) echo "refusing to replace $DEST" >&2; exit 1 ;; esac
mkdir -p "$DEST_DIR"
rm -rf "$DEST"
ditto "$SOURCE" "$DEST"

APPEX="$DEST/Contents/PlugIns/VibeWidgetExtension.appex"
[ -d "$APPEX" ] || { echo "no widget extension inside $DEST" >&2; exit 1; }

if [ -n "$SIGN" ]; then
  APP_ENTITLEMENTS="$root/App/VibeWidget.entitlements"
  WIDGET_ENTITLEMENTS="$root/Widget/VibeWidgetExtension.entitlements"
  for path in "$APP_ENTITLEMENTS" "$WIDGET_ENTITLEMENTS"; do
    [ -e "$path" ] || { echo "missing entitlement template: $path" >&2; exit 1; }
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
EOF
    exit 1
  fi

  GROUP="$TEAM.group.com.phonpreecha.vibewidget"
  echo "==> re-signing as team $TEAM"

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
# Read it out first: `grep -q` closes the pipe early, and under pipefail that
# turns codesign's SIGPIPE into a failed check on a perfectly good bundle.
elif [ -z "$(codesign -dv "$DEST" 2>&1 | sed -n 's/^TeamIdentifier=\([A-Z0-9][A-Z0-9]*\)$/\1/p')" ]; then
  cat >&2 <<'EOF'
warning: this bundle carries no Team ID, so macOS will not load its widget.
         The menu bar app still works. To sign it with your own certificate:

           vibewidget-refresh --sign
EOF
fi

echo "==> registering the widget extension"
"$LSREGISTER" -f "$DEST"

echo "==> launching"
open "$DEST"
sleep 3

echo "==> widget extension registration:"
pluginkit -mAvvv 2>/dev/null | grep -A1 -i vibe || echo "    NOT REGISTERED"

# The version people actually see comes from this copy, not from the Cellar, so
# saying it out loud is what makes a skipped refresh obvious.
echo
echo "VibeWidget $SOURCE_VERSION is installed and running."
