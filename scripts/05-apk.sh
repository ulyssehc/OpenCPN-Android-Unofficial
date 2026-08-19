#!/usr/bin/env bash
# Assemble the debug APK (armeabi-v7a + arm64-v8a).
# Needs egress to dl.google.com / maven.google.com for AGP and AndroidX.
set -euo pipefail
. "$(dirname "$0")/env.sh"

test -f "$OCPN/$BUILD_64/libgorp.so" \
  || echo "WARNING: $OCPN/$BUILD_64/libgorp.so missing -- run 03-core.sh first"

cd "$APP"
chmod +x gradlew
./gradlew --no-daemon assembleDebug

echo ">>> APK(s):"
find "$APP/app/build/outputs/apk" -name '*.apk' | sed 's/^/    /'
