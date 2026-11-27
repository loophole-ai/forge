#!/usr/bin/env bash
# Generate the Loophole Android project (Capacitor) around the already-built web app.
#
# Nothing here is committed to loophole-app: the native project is created fresh on every
# run, so loophole-app stays free of mobile build files.
#
# Env:
#   APP_DIR   loophole-app checkout, with packages/app/dist already built (required)
#   VERSION   x.y.z version for the APK (required)
#   WORK_DIR  where to create the project (default: ./mobile)
#   APP_ID    Android application id (default: ai.loophole.mobile)
#   APP_NAME  launcher name (default: Loophole)
#   CAPACITOR_VERSION  Capacitor major to install (default: 7)
set -euo pipefail

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
log() { printf '==> %s\n' "$*"; }

APP_DIR="${APP_DIR:?set APP_DIR to the loophole-app checkout}"
VERSION="${VERSION:?set VERSION to x.y.z}"
WORK_DIR="${WORK_DIR:-$PWD/mobile}"
APP_ID="${APP_ID:-ai.loophole.mobile}"
APP_NAME="${APP_NAME:-Loophole}"
CAPACITOR_VERSION="${CAPACITOR_VERSION:-7}"

DIST="$APP_DIR/packages/app/dist"
ICON="$APP_DIR/assets/packages/desktop/icons/prod/icon.png"
BACKGROUND="#080808"

[[ "$VERSION" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] || die "VERSION must look like 1.2.3 (got '$VERSION')"
VERSION_CODE=$(( BASH_REMATCH[1] * 10000 + BASH_REMATCH[2] * 100 + BASH_REMATCH[3] ))

[ -f "$DIST/index.html" ] || die "web app is not built: $DIST/index.html is missing"
[ -f "$ICON" ] || die "Loophole icon not found: $ICON"
command -v convert >/dev/null || die "ImageMagick 'convert' is required"

log "creating Capacitor project in $WORK_DIR"
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"
npm init -y >/dev/null
npm install --no-audit --no-fund \
  "@capacitor/core@$CAPACITOR_VERSION" "@capacitor/cli@$CAPACITOR_VERSION" "@capacitor/android@$CAPACITOR_VERSION" >/dev/null

# androidScheme "http" makes the WebView origin http://localhost, so the app can call a plain-http
# Loophole server on the local network without mixed-content blocking.
cat > capacitor.config.json <<JSON
{
  "appId": "$APP_ID",
  "appName": "$APP_NAME",
  "webDir": "$DIST",
  "server": { "androidScheme": "http", "cleartext": true }
}
JSON

npx cap add android
npx cap sync android

RES="android/app/src/main/res"
MANIFEST="android/app/src/main/AndroidManifest.xml"

log "version $VERSION (code $VERSION_CODE)"
sed -i -E "s/versionCode [0-9]+/versionCode $VERSION_CODE/; s/versionName \"[^\"]*\"/versionName \"$VERSION\"/" android/app/build.gradle
grep -q "versionCode $VERSION_CODE" android/app/build.gradle || die "could not set versionCode"
grep -q "versionName \"$VERSION\"" android/app/build.gradle || die "could not set versionName"

# Android 9+ blocks plain-http requests unless the app opts in; the Loophole server on a LAN is http.
log "allowing cleartext traffic to the user's own server"
sed -i 's|<application|<application android:usesCleartextTraffic="true"|' "$MANIFEST"
grep -q 'usesCleartextTraffic="true"' "$MANIFEST" || die "could not patch AndroidManifest.xml"

log "launcher icons"
# Use the plain PNG launcher icons: drop Capacitor's adaptive-icon definitions and its foreground layers.
rm -rf "$RES/mipmap-anydpi-v26"
find "$RES" -name 'ic_launcher_foreground.png' -delete
for pair in mdpi:48 hdpi:72 xhdpi:96 xxhdpi:144 xxxhdpi:192; do
  density="${pair%%:*}"; size="${pair##*:}"
  for name in ic_launcher ic_launcher_round; do
    convert "$ICON" -resize "${size}x${size}" "PNG32:$RES/mipmap-$density/$name.png"
  done
done

log "launch screen"
# Replace Capacitor's default splash artwork with a flat colour that matches the app background.
while IFS= read -r -d '' file; do
  convert -size 2x2 "xc:$BACKGROUND" "PNG32:$file"
done < <(find "$RES" -path '*drawable*' -name 'splash.png' -print0)

log "android project ready: $WORK_DIR/android"
