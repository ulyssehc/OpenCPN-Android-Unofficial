#!/usr/bin/env bash
# Repoint the Gradle app at local checkouts and remove the pieces that cannot
# be built outside the upstream maintainer's machine. Idempotent.
set -euo pipefail
. "$(dirname "$0")/env.sh"

G="$APP/app/build.gradle"
test -f "$G" || { echo "FATAL: $G not found, run 02-sources.sh first"; exit 1; }
[ -f "$G.orig" ] || cp "$G" "$G.orig"
cp "$G.orig" "$G"          # always patch from pristine, so re-runs are clean

# 1. Repoint the two base paths. Everything else in the file is relative to
#    these, which is why only two lines need to change.
sed -i "s|def Qt_Base = \".*\"|def Qt_Base = \"$COMMON/qt5\"|" "$G"
sed -i "s|def OCPN_Base = \".*\"|def OCPN_Base = \"$OCPN\"|" "$G"

# 2. Drop Firebase. The app applies com.google.gms.google-services but ships no
#    google-services.json, so the plugin hard-fails. Crashlytics goes with it.
sed -i "/id 'com.google.firebase.crashlytics'/d;/id 'com.google.gms.google-services'/d" "$G"
sed -i "/com.google.firebase:firebase-/d;/platform(\"com.google.firebase:firebase-bom/d" "$G"
sed -i "/id 'com.google.firebase.crashlytics'/d;/id 'com.google.gms.google-services'/d" "$APP/build.gradle"

# 3. oexserverd belongs to the proprietary o-charts plugin and is not public.
#    Cost of dropping it: no o-charts encrypted charts. BSB/S57/CM93 unaffected.
sed -i "s|^\( *\)preBuild.dependsOn(copySERVERFiles32)|\1//preBuild.dependsOn(copySERVERFiles32)|" "$G"
sed -i "s|^\( *\)preBuild.dependsOn(copySERVERFiles64)|\1//preBuild.dependsOn(copySERVERFiles64)|" "$G"

# 4. JCenter was shut down in 2021; leaving it in only adds resolution stalls.
sed -i "/^\s*jcenter()\s*$/d" "$APP/build.gradle" "$APP/settings.gradle"

# 5. Upstream layout drift: the app still refers to src/bitmaps/, which the
#    current core tree calls resources/bitmaps/. Gradle Copy SKIPS a missing
#    source silently, so leaving this produces an APK with no toolbar icons
#    and no styles.xml rather than a build failure.
sed -i "s|\${OCPN_Base}/src/bitmaps/|\${OCPN_Base}/resources/bitmaps/|g" "$G"

echo ">>> Patched $G"
grep -n 'def Qt_Base\|def OCPN_Base' "$G" | sed 's/^/    /'
