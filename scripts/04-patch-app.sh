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

# 7. The materialfilemanager module's night theme extends
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

# 8. DEFAULT ON (OPCN_FIX_STATUSBAR_DOUBLE=0 disables): the status bar height is
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
        else if (android.os.Build.VERSION.SDK_INT < 35) {
            // Pre-Android-15 only. Here dm.heightPixels EXCLUDES the status
            // bar and the format string below subtracts it again, so the
            // canvas ends up one status bar short and the window background
            // shows as a black band above the navigation buttons.
            //
            // From SDK 35 the window is edge-to-edge and dm.heightPixels
            // already INCLUDES the status bar -- upstream compensates for
            // that a few lines above with
            //     if (SDK_INT >= 35) actionBarHeight += getNavBarHeight();
            // Adding it back there overshoots by one status bar and the
            // canvas overflows the screen (verified on Android 17).
            height += statusBarHeight;
        }
        else {
            // SDK 35+ (edge-to-edge). Do NOT compute this from inset
            // resources. On this path statusBarHeight is the legacy
            // status_bar_height dimen, which a display cutout makes wrong,
            // and actionBarHeight already carries getNavBarHeight(), added a
            // few lines above. Two corrections derived from those numbers
            // were built and both missed on Android 17 (one canvas too tall,
            // one too short).
            //
            // Measure instead. setupEdgeToEdge() pads android.R.id.content
            // with the real system-bar insets, so its height minus its own
            // padding IS the area available to the Qt surface, whatever the
            // cutout, the action bar or the navigation mode turn out to be.
            // The format string below sends (height - statusBarHeight) and
            // the native side subtracts actionBarHeight, so sending
            // avail + statusBarHeight + actionBarHeight makes the canvas
            // come out exactly equal to the measured area.
            //
            // Measured, not derived from gFrame: androidForceFullRepaint()
            // resizes the frame by -1 px before re-querying, so reading back
            // a view Qt resizes would ratchet the canvas smaller on every
            // repaint. android.R.id.content is sized by the decor, not by Qt.
            //
            // Before the first layout pass getHeight() is 0 and this leaves
            // `height` untouched; OpenCPN re-queries through
            // androidConfirmSizeCorrection() once laid out.
            View cv = findViewById(android.R.id.content);
            if (cv != null) {
                int avail = cv.getHeight() - cv.getPaddingTop() - cv.getPaddingBottom();
                if (avail > 0) {
                    height = avail + statusBarHeight + actionBarHeight;
                }
            }
        }
"""
if old not in s:
    sys.exit("FATAL: fullscreen height fixup block not found")
s = s.replace(old, new, 1)
open(p, "w").write(s)
PYEOF
  grep -q "SDK_INT < 35" "$Q" \
    && echo ">>> Applied status-bar double-subtraction fix" \
    || { echo "FATAL: status-bar fix not applied"; exit 1; }
fi

# 9. Supply the four style icons upstream never published. androidUTIL.cpp
#    loads <SharedDataDir>/styles/{chek_full,chek_empty,tabbar_button_left,
#    tabbar_button_right}.png for the Qt checkbox indicator and tab-bar scroll
#    arrows, but they exist in none of the upstream repositories -- the core's
#    data/styles/ holds only qtstylesheet.qss. Missing, they render as empty
#    boxes and log only "can't open file". These are our own drawings; see
#    assets/styles/README.md.
ICONS="$(cd "$(dirname "$0")/.." && pwd)/assets/styles"
if [ -d "$ICONS" ]; then
  mkdir -p "$OCPN/data/styles"
  cp "$ICONS"/*.png "$OCPN/data/styles/"
  echo ">>> Installed $(ls "$ICONS"/*.png | wc -l) replacement style icons"
fi

echo ">>> Patched $G"
grep -n 'def Qt_Base\|def OCPN_Base' "$G" | sed 's/^/    /'

# 10. OPT-IN diagnostic (OPCN_GEOM_DIAG=1, OFF by default). Dumps the real
#     view geometry to an on-screen dialog with a Copy button, because the
#     OpenCPN log file is not reachable on Android 15+ scoped storage and the
#     display-geometry defect (#8 above) cannot be settled by arithmetic on
#     the values upstream already exposes. Never enabled for a release build;
#     06-release.sh refuses a tree that still contains the marker.
if [ "${OPCN_GEOM_DIAG:-0}" = "1" ] && [ -f "$Q" ]; then
  python3 - "$Q" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p).read()

anchor = "    public String getDeviceInfo() {"
if anchor not in s:
    sys.exit("FATAL: getDeviceInfo anchor not found")

methods = '''    // ---- OPCN_GEOM_DIAG ----
    private boolean m_opcnGeomShown = false;

    private void opcnDumpTree(View v, int depth, StringBuilder sb) {
        if (v == null || depth > 4) return;
        for (int i = 0; i < depth; i++) sb.append("  ");
        sb.append(v.getClass().getSimpleName())
          .append(" id=").append(Integer.toHexString(v.getId()))
          .append(" top=").append(v.getTop())
          .append(" h=").append(v.getHeight())
          .append(" padT=").append(v.getPaddingTop())
          .append(" padB=").append(v.getPaddingBottom())
          .append("\\n");
        if (v instanceof ViewGroup) {
            ViewGroup g = (ViewGroup) v;
            for (int i = 0; i < g.getChildCount(); i++)
                opcnDumpTree(g.getChildAt(i), depth + 1, sb);
        }
    }

    private void opcnShowGeom() {
        StringBuilder sb = new StringBuilder();
        DisplayMetrics dm = new DisplayMetrics();
        getWindowManager().getDefaultDisplay().getMetrics(dm);
        int sbh = 0;
        int rid = getResources().getIdentifier("status_bar_height", "dimen", "android");
        if (rid > 0) sbh = getResources().getDimensionPixelSize(rid);
        androidx.appcompat.app.ActionBar ab = getSupportActionBar();
        sb.append("sdk=").append(Build.VERSION.SDK_INT)
          .append(" dm=").append(dm.widthPixels).append("x").append(dm.heightPixels)
          .append(" dens=").append(dm.density).append("\\n")
          .append("statusBar=").append(sbh)
          .append(" navBar=").append(getNavBarHeight())
          .append(" actionBarRaw=").append(ab == null ? -1 : ab.getHeight())
          .append(" showing=").append(ab != null && ab.isShowing()).append("\\n")
          .append("insets=").append(m_insets == null ? "null"
                : (m_insets.left + "," + m_insets.top + "," + m_insets.right + "," + m_insets.bottom))
          .append("\\n").append("sent=").append(getDisplayMetrics()).append("\\n\\n");
        opcnDumpTree(getWindow().getDecorView(), 0, sb);
        final String text = sb.toString();
        Log.i("OpenCPN", "GEOM\\n" + text);
        new AlertDialog.Builder(this)
            .setTitle("OPCN geometry")
            .setMessage(text)
            .setPositiveButton("Copy", (d, w) -> {
                android.content.ClipboardManager cm = (android.content.ClipboardManager)
                        getSystemService(android.content.Context.CLIPBOARD_SERVICE);
                cm.setPrimaryClip(android.content.ClipData.newPlainText("geom", text));
            })
            .setNegativeButton("Close", null)
            .show();
    }
    // ---- end OPCN_GEOM_DIAG ----

'''
s = s.replace(anchor, methods + anchor, 1)

trig_anchor = '''        //Log.i("DEBUGGER_TAG", ret);


        return ret;
    }
'''
trig = '''        //Log.i("DEBUGGER_TAG", ret);

        if (!m_opcnGeomShown && findViewById(android.R.id.content) != null
                && findViewById(android.R.id.content).getHeight() > 0) {
            m_opcnGeomShown = true;
            new android.os.Handler(android.os.Looper.getMainLooper())
                    .postDelayed(this::opcnShowGeom, 10000);
        }

        return ret;
    }
'''
if trig_anchor not in s:
    sys.exit("FATAL: getDisplayMetrics return anchor not found")
s = s.replace(trig_anchor, trig, 1)
open(p, "w").write(s)
PYEOF
  grep -q "OPCN_GEOM_DIAG" "$Q" \
    && echo ">>> Applied geometry diagnostic (DIAGNOSTIC BUILD, do not release)" \
    || { echo "FATAL: geometry diagnostic not applied"; exit 1; }
fi
