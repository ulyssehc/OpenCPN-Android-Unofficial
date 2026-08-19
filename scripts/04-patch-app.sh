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

# 6. The app's Java also USES FirebaseAnalytics (4 references in QtActivity.java:
#    an import, a field, a comment and a getInstance call whose result is never
#    read again). Removing the dependency alone breaks compilation, so strip the
#    usage too. The alternative -- a fabricated google-services.json -- would
#    make the build succeed while shipping analytics wired to a bogus project.
Q="$APP/app/src/main/java/org/qtproject/qt5/android/bindings/QtActivity.java"
if [ -f "$Q" ]; then
  [ -f "$Q.orig" ] || cp "$Q" "$Q.orig"
  cp "$Q.orig" "$Q"
  sed -i "/^import com\.google\.firebase\.analytics\.FirebaseAnalytics;/d" "$Q"
  sed -i "/private FirebaseAnalytics mFirebaseAnalytics;/d" "$Q"
  sed -i "/\/\/ Obtain the FirebaseAnalytics instance\./d" "$Q"
  sed -i "/mFirebaseAnalytics = FirebaseAnalytics\.getInstance(this);/d" "$Q"
  left=$(grep -c "Firebase" "$Q" || true)
  echo ">>> Stripped Firebase from QtActivity.java (references left: $left)"
  [ "$left" -eq 0 ] || { echo "FATAL: Firebase references remain"; exit 1; }
fi

# 7. OPTIONAL (OPCN_FIX_INSET_PADDING=1): remove the double inset that leaves a
#    black bar above the navigation buttons. setupEdgeToEdge() pads the content
#    view by the system-bar insets, while the SAME insets and navBarHeight are
#    also handed to the native layer (getDisplayMetrics), which lays out around
#    them itself -- so the nav bar height is reserved twice and the window
#    background shows through. Removing the padding keeps edge-to-edge and lets
#    the native side do the insetting. m_insets must keep being assigned by the
#    listener: the metrics string dereferences it, so dropping the listener
#    entirely would NPE at startup.
if [ "${OPCN_FIX_INSET_PADDING:-0}" = "1" ] && [ -f "$Q" ]; then
  sed -i "s|^\( *\)v\.setPadding(m_insets\.left, m_insets\.top, m_insets\.right, m_insets\.bottom);|\1// v.setPadding(...) removed: native layer already applies these insets|" "$Q"
  if grep -q "v.setPadding(m_insets" "$Q"; then
    echo "FATAL: inset padding line not patched"; exit 1
  fi
  echo ">>> Removed duplicate inset padding (OPCN_FIX_INSET_PADDING)"
fi

# 8. The materialfilemanager module's night theme extends
#    Theme.MaterialComponents.DayNight.DarkActionBar and uses Material attrs
#    (colorPrimaryVariant, colorOnPrimary), but the module only depends on the
#    pre-AndroidX support library. Debug builds never notice; release runs
#    verifyReleaseResources and fails resource linking. Add the same Material
#    version the app module already uses.
M="$APP/materialfilemanager/build.gradle"
if [ -f "$M" ] && ! grep -q 'com.google.android.material:material' "$M"; then
  [ -f "$M.orig" ] || cp "$M" "$M.orig"
  sed -i "s|^\( *\)implementation 'com.android.support:appcompat-v7:26.1.0'|\1implementation 'com.android.support:appcompat-v7:26.1.0'\n\1implementation 'com.google.android.material:material:1.10.0'|" "$M"
  grep -q 'com.google.android.material:material' "$M" \
    && echo ">>> Added Material Components to materialfilemanager" \
    || { echo "FATAL: could not add Material dependency"; exit 1; }
fi

# 9. DEFAULT ON (OPCN_FIX_STATUSBAR_DOUBLE=0 disables): the status bar height is
#    subtracted twice outside fullscreen mode. getDisplayMetrics sends
#    "height - statusBarHeight", but outside m_fullScreen `height` comes from
#    dm.heightPixels, which ALREADY excludes the status bar. The m_fullScreen
#    branch adds it back ("height += statusBarHeight") before the same
#    subtraction; the normal path does not. Native then sizes the canvas as
#    (height - statusBar) - actionBar, so the canvas ends up one status bar
#    short and the window background shows as a black band above the
#    navigation buttons. Mirroring the fullscreen correction makes the sent
#    value the true content height.
#    Related: setupEdgeToEdge() runs on every Android version, but the
#    edge-to-edge compensation (actionBarHeight += getNavBarHeight()) is gated
#    to SDK >= 35, so Android 13 gets the layout without the correction.
#    VERIFIED on device (Android 13 / e OS): the black band is gone. ON by
#    default; set OPCN_FIX_STATUSBAR_DOUBLE=0 to build without it.
if [ "${OPCN_FIX_STATUSBAR_DOUBLE:-1}" = "1" ] && [ -f "$Q" ]; then
  python3 - "$Q" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p).read()
old = """            height += statusBarHeight;
        }
"""
new = """            height += statusBarHeight;
        }
        else {
            // dm.heightPixels already excludes the status bar; the format
            // string below subtracts it again. Add it back so the reported
            // height is the real content height.
            height += statusBarHeight;
        }
"""
if old not in s:
    sys.exit("FATAL: fullscreen height fixup block not found")
s = s.replace(old, new, 1)
open(p, "w").write(s)
PYEOF
  grep -q "already excludes the status bar" "$Q" \
    && echo ">>> Applied status-bar double-subtraction fix" \
    || { echo "FATAL: status-bar fix not applied"; exit 1; }
fi

echo ">>> Patched $G"
grep -n 'def Qt_Base\|def OCPN_Base' "$G" | sed 's/^/    /'
