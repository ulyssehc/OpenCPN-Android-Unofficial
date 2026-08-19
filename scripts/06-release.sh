#!/usr/bin/env bash
# Build and sign a release (non-debuggable) APK.
#
# Signing key: pass OPCN_KEYSTORE (path), OPCN_KS_PASS, OPCN_KS_ALIAS.
# If OPCN_KEYSTORE is unset, a keystore is generated once at $ROOT/opencpn-release.jks
# and its password written next to it. KEEP THAT FILE: Android ties updates to the
# signing key, so every later build must use the same one or it will not install
# as an update (uninstall-and-lose-data instead). Never commit it.
set -euo pipefail
. "$(dirname "$0")/env.sh"

KS="${OPCN_KEYSTORE:-$ROOT/opencpn-release.jks}"
ALIAS="${OPCN_KS_ALIAS:-opencpn}"
BT="$SDK/build-tools/$BUILD_TOOLS"

if [ ! -f "$KS" ]; then
  PW="$(python3 -c "import secrets,string;print(''.join(secrets.choice(string.ascii_letters+string.digits) for _ in range(28)))")"
  echo "$PW" > "$KS.password"
  chmod 600 "$KS.password"
  keytool -genkeypair -keystore "$KS" -alias "$ALIAS" -keyalg RSA -keysize 4096 \
    -validity 10000 -storepass "$PW" -keypass "$PW" \
    -dname "CN=OpenCPN Self Build, OU=Personal, O=Personal, L=Unknown, ST=Unknown, C=CH"
  echo ">>> Generated keystore $KS (password in $KS.password) -- BACK THIS UP"
fi
PW="${OPCN_KS_PASS:-$(cat "$KS.password")}"

# Strip native libs exactly as the debug path does (see 05-apk.sh).
if [ "${OPCN_KEEP_SYMBOLS:-0}" != "1" ]; then
  for d in "$BUILD_32" "$BUILD_64"; do
    for f in "$OCPN/$d/libgorp.so" $(find "$OCPN/$d/plugins" -name 'lib*_pi.so' 2>/dev/null); do
      [ -f "$f" ] && "$TOOL_BASE/bin/llvm-strip" --strip-unneeded "$f"
    done
  done
fi

cd "$APP"
chmod +x gradlew
./gradlew --no-daemon clean assembleRelease

UNSIGNED=$(find "$APP/app/build/outputs/apk/release" -name '*-unsigned.apk' | head -1)
test -n "$UNSIGNED" || { echo "FATAL: no unsigned release APK produced"; exit 1; }
OUT="$ROOT/opencpn-$(basename "$UNSIGNED" | sed 's/.*v[0-9]*(\(.*\))-release-unsigned.apk/\1/')-release.apk"

"$BT/zipalign" -p -f 4 "$UNSIGNED" "$OUT"
"$BT/apksigner" sign --ks "$KS" --ks-key-alias "$ALIAS" \
  --ks-pass "pass:$PW" --key-pass "pass:$PW" \
  --v1-signing-enabled true --v2-signing-enabled true --v3-signing-enabled true "$OUT"

# Verify rather than assume: signature, alignment, and that it is NOT debuggable.
"$BT/apksigner" verify "$OUT" >/dev/null || { echo "FATAL: signature does not verify"; exit 1; }
"$BT/zipalign" -c 4 "$OUT" >/dev/null || { echo "FATAL: APK is not aligned"; exit 1; }
if "$BT/aapt" dump badging "$OUT" 2>/dev/null | grep -q application-debuggable; then
  echo "FATAL: release APK is debuggable"; exit 1
fi

echo ">>> Release APK: $OUT ($(stat -c%s "$OUT") bytes)"
sha256sum "$OUT"
