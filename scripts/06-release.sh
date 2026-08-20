#!/usr/bin/env bash
# Build and sign a release (non-debuggable) APK.
#
# Signing key: pass OPCN_KEYSTORE (path), OPCN_KS_PASS, OPCN_KS_ALIAS.
# Android ties updates to the signing key: an APK signed with a different key will
# not install over an existing one -- the device reports the package as invalid or
# not installed, which reads exactly like a corrupted download. So a MISSING
# keystore is a hard error here, not something to paper over by minting a new one.
# Set OPCN_KS_GENERATE=1 to create the very first keystore, then keep the file:
# it is the only thing that can ever update the app. Never commit it.
#
# The expected certificate is pinned in expected-signing-cert.sha256 (a public
# certificate fingerprint, safe to commit) and checked after signing. That pin is
# what turns "signed with the wrong key" from a silent bad build into a failure.
set -euo pipefail
# Resolve before anything cd's: the gradle step runs from $APP, so a relative
# $(dirname "$0") would point outside this repository by the time it is used.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/env.sh"

KS="${OPCN_KEYSTORE:-$ROOT/opencpn-release.jks}"
ALIAS="${OPCN_KS_ALIAS:-opencpn}"
BT="$SDK/build-tools/$BUILD_TOOLS"

if [ ! -f "$KS" ] && [ "${OPCN_KS_GENERATE:-0}" != "1" ]; then
  echo "FATAL: signing keystore not found: $KS"
  echo "       An APK signed with a different key CANNOT update an installed one."
  echo "       Restore the keystore (and its .password file) and re-run, or set"
  echo "       OPCN_KS_GENERATE=1 if this really is the first key for this app."
  exit 1
fi

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

# A diagnostic build must never be released: step 10 of 04-patch-app.sh injects
# an on-screen geometry dump, and a tree still carrying it would ship it.
if [ "${OPCN_ALLOW_DIAG_RELEASE:-0}" != "1" ] && \
   grep -q "OPCN_GEOM_DIAG" "$APP/app/src/main/java/org/qtproject/qt5/android/bindings/QtActivity.java" 2>/dev/null; then
  echo "FATAL: the app tree still carries the OPCN_GEOM_DIAG diagnostic."
  echo "       Re-run scripts/04-patch-app.sh without OPCN_GEOM_DIAG=1, or set"
  echo "       OPCN_ALLOW_DIAG_RELEASE=1 to sign a diagnostic build on purpose."
  exit 1
fi

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

# Pin the signing identity. apksigner verify only proves the APK is self-consistent;
# it says nothing about WHICH key signed it, so it passes happily on an APK signed
# with a freshly generated keystore that no installed copy will accept as an update.
PIN="$SCRIPT_DIR/../expected-signing-cert.sha256"
GOT="$("$BT/apksigner" verify --print-certs "$OUT" 2>/dev/null \
        | sed -n 's/^Signer #1 certificate SHA-256 digest: //p' | head -1)"
if [ -f "$PIN" ]; then
  WANT="$(tr -d '[:space:]' < "$PIN")"
  if [ "$GOT" != "$WANT" ]; then
    echo "FATAL: signed with the WRONG key."
    echo "       expected $WANT"
    echo "       got      $GOT"
    echo "       This APK would not install over an existing one. Restore the"
    echo "       correct keystore, or update the pin if the key changed on purpose."
    exit 1
  fi
  echo ">>> Signing certificate matches the pin ($GOT)"
else
  echo ">>> No pin at $PIN -- recording this build's certificate"
  echo "$GOT" > "$PIN"
fi
"$BT/zipalign" -c 4 "$OUT" >/dev/null || { echo "FATAL: APK is not aligned"; exit 1; }
if "$BT/aapt" dump badging "$OUT" 2>/dev/null | grep -q application-debuggable; then
  echo "FATAL: release APK is debuggable"; exit 1
fi

echo ">>> Release APK: $OUT ($(stat -c%s "$OUT") bytes)"
sha256sum "$OUT"
