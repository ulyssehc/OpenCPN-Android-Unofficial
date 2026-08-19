#!/usr/bin/env bash
# Assemble the debug APK (armeabi-v7a + arm64-v8a).
# Needs egress to dl.google.com / maven.google.com for AGP and AndroidX.
set -euo pipefail
. "$(dirname "$0")/env.sh"

test -f "$OCPN/$BUILD_64/libgorp.so" \
  || echo "WARNING: $OCPN/$BUILD_64/libgorp.so missing -- run 03-core.sh first"

# Strip debug symbols from the native libraries. Unstripped, libgorp.so alone
# is ~225 MB per ABI and the APK lands at 217 MB against ~55 MB for the Play
# Store build. Set OPCN_KEEP_SYMBOLS=1 to keep them (e.g. to debug a crash).
if [ "${OPCN_KEEP_SYMBOLS:-0}" != "1" ]; then
  STRIP="$TOOL_BASE/bin/llvm-strip"
  for d in "$BUILD_32" "$BUILD_64"; do
    for f in "$OCPN/$d/libgorp.so" $(find "$OCPN/$d/plugins" -name 'lib*_pi.so' 2>/dev/null); do
      [ -f "$f" ] && "$STRIP" --strip-unneeded "$f"
    done
  done
  echo ">>> Stripped native libraries"
fi

cd "$APP"
chmod +x gradlew
# 'clean' is deliberate, not caution: AGP's incremental packaging leaves the
# previous run's entry data in the .apk file. After stripping, the rebuilt APK
# still measured 217 MB while holding only 81 MB of live entries -- valid, since
# a zip is read from its trailing central directory, but 136 MB of dead bytes.
./gradlew --no-daemon clean assembleDebug

echo ">>> APK(s):"
find "$APP/app/build/outputs/apk" -name '*.apk' | sed 's/^/    /'
