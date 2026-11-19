#!/bin/zsh
# Construit mUGGINFACE.app (ou, avec DEV=1, « mUGGINFACE dev.app », identifiant …dev, données séparées), la signe
# (certificat local stable) puis l'installe dans ~/Applications/Applications Personnelles.
# NO_INSTALL=1 : ne pas installer ; NO_OPEN=1 : ne pas lancer.
set -euo pipefail
cd "$(dirname "$0")"
DEST="$HOME/Applications/Applications Personnelles"
if [ -n "${DEV:-}" ]; then NAME="mUGGINFACE dev"; else NAME="mUGGINFACE"; fi
APP="$NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -swift-version 5 -parse-as-library -target arm64-apple-macos15 -o "$APP/Contents/MacOS/mUGGINFACE" Sources/*.swift
cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# Descriptions des autorisations dans les 4 langues
for l in fr en es it; do mkdir -p "$APP/Contents/Resources/$l.lproj"; cp "Resources/$l.lproj/InfoPlist.strings" "$APP/Contents/Resources/$l.lproj/InfoPlist.strings"; done
if [ -n "${DEV:-}" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier fr.stephan.mugginface.dev" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName mUGGINFACE dev" "$APP/Contents/Info.plist"
fi
SIGN="/Volumes/SKYRIM/TOOLS/MAC/_tools/sign_app.sh"
if [ -x "$SIGN" ]; then "$SIGN" "$APP"; else codesign --force --deep -s - "$APP"; fi
if [ -z "${NO_INSTALL:-}" ] && [ -z "${DEV:-}" ]; then
  mkdir -p "$DEST"
  pkill -x mUGGINFACE 2>/dev/null || true
  rm -rf "$DEST/$APP"
  cp -R "$APP" "$DEST/$APP"
  echo "Installée : $DEST/$APP"
fi
echo "OK : $APP"
