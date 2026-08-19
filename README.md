# opcn — reproducible OpenCPN Android build

Scripts that build an OpenCPN APK (armeabi-v7a + arm64-v8a) from source, with
every upstream version pinned.

OpenCPN's official Android app is distributed only through Google Play, as a
paid app. There is no APK download. This repository builds one from the public
sources instead.

## Status

**These scripts produce a working APK.** Built and verified end to end:

    org.opencpn.opencpn  versionCode 128  versionName 5.14.0
    minSdk 21   targetSdk 36   native-code: arm64-v8a, armeabi-v7a
    debug   : 81.8 MB, debug-signed
    release : 75.3 MB, not debuggable, signed + zipaligned (verified)

Verified in the built APK: both `libgorp.so` cores (22.4 MB armv7a / 26.3 MB
arm64, stripped), all 8 plugin binaries (4 plugins x 2 ABIs), the Qt5 runtime
libraries, and 475 UI asset entries.

**Verified on hardware**: the signed release build installs and runs correctly
on Android 13 (/e/OS), including the display-geometry fix below. No known
functional defects outstanding.

## Requirements

- Linux x86_64, JDK 17+, cmake, make, git, curl, unzip, **gettext**
  (`scripts/00-hostdeps.sh` installs these; gettext is not optional -- the core
  cmake calls `find_package(Gettext)` and configure fails without msgfmt)
- ~15 GB free disk
- Network access to:
  - `dl.google.com` and `maven.google.com` — SDK, NDK, Android Gradle Plugin,
    AndroidX. `maven.google.com` 301-redirects to `dl.google.com`, so **both**
    must be allowed or artifact resolution fails at the redirect.
  - `github.com` / `objects.githubusercontent.com` — sources and support bundle
  - `codeload.github.com` — cmake fetches shapelib and rapidjson as GitHub
    archive tarballs from here. If archive downloads are refused, run with
    `OPCN_OFFLINE_DEPS=1`: `02-sources.sh` clones both from git instead and
    `03-core.sh` passes `FETCHCONTENT_SOURCE_DIR_*`.

    Note that allowing the *host* may not be enough. On the network this was
    built on, the TLS tunnel to codeload succeeded while the archive request
    itself still returned 403 — a gateway permitting the git protocol but not
    archive endpoints. Plain `git clone` worked throughout, which is why the
    workaround uses it. Prefer the default when archives are available: it
    keeps upstream's `URL_HASH` check, which `FETCHCONTENT_SOURCE_DIR` bypasses
    in favour of a (mutable) git tag.
  - `repo1.maven.org`, `plugins.gradle.org`, `services.gradle.org`

Qt's and OpenCPN's own download servers are NOT needed: every native
prerequisite comes from GitHub.

## Usage

    OPCN_ROOT=~/opcn-build ./build.sh

    # where GitHub archive downloads are blocked (see Requirements):
    OPCN_ROOT=~/opcn-build OPCN_OFFLINE_DEPS=1 ./build.sh

Or one stage at a time — `scripts/01-toolchain.sh` … `scripts/05-apk.sh`.

For a signed, non-debuggable build:

    scripts/06-release.sh

It generates a keystore on first run (at `$OPCN_ROOT/opencpn-release.jks`, with
the password beside it) or uses `OPCN_KEYSTORE` / `OPCN_KS_PASS` / `OPCN_KS_ALIAS`.
**Back that keystore up and keep it out of git.** Android ties updates to the
signing key: build with a different key and the APK will not install as an
update, only as an uninstall-and-reinstall, losing routes, waypoints and
settings. The script verifies the signature, the alignment, and that the result
is genuinely not debuggable, rather than assuming any of the three.
Configuration and pinned versions live in `scripts/env.sh`.

## Pinned versions

| Component | Version | Source |
|---|---|---|
| OpenCPN core | v5.14.x @ `4f7e6f0` (2026-08-13) | stable branch matching the app |
| Android NDK | 26.1.10909125 | pinned by OpenCPN CI |
| SDK cmdline-tools | 11076708 | |
| compileSdk / buildTools | 35 / 34.0.0 | `OpenCPN-Android/app/build.gradle` |
| Gradle / AGP | 8.11.1 / 8.9.1 | upstream wrapper |
| App version | 5.14.0 (versionCode 128) | `bdbcat/OpenCPN-Android` |

## Upstream pieces

| Repository | Role |
|---|---|
| `OpenCPN/OpenCPN` | core; builds `libgorp.so` (cmake `PACKAGE_NAME` is `gorp`) and the four bundled plugins |
| `bdbcat/OpenCPN-Android` | the Gradle app — Java/Kotlin front end, assets, packaging |
| `bdbcat/OCPNAndroidCommon` | prebuilt Qt5 + wxQt the APK links against |
| `bdbcat/OCPNAndroidCoreBuildSupport` | prebuilt wxWidgets + OpenSSL for the core build |

Note: `buildandroid/` inside the main OpenCPN repo is NOT this build. It is
abandoned Eclipse-era scaffolding (`targetSdkVersion 19`, qmake, hardcoded
paths). The live Android build is `bdbcat/OpenCPN-Android`.

## Deliberate omissions

`scripts/04-patch-app.sh` removes things that cannot be built outside the
upstream maintainer's own machine. Each is a decision, not an oversight:

1. **Firebase / Crashlytics / Analytics.** The app applies
   `com.google.gms.google-services` but ships no `google-services.json`, so the
   plugin hard-fails. Removing the plugin and dependencies is not sufficient:
   `QtActivity.java` also USES `FirebaseAnalytics` (import, field, and a
   `getInstance` call whose result is never read again), so the patch strips
   those four references too and asserts none remain. The alternative -- a
   fabricated `google-services.json` -- would build, but ship analytics wired to
   a bogus project. No crash reporting, no analytics.
2. **`oexserverd`.** Copied from the proprietary o-charts plugin, which is not
   public. Dropped, so **o-charts encrypted charts will not work**. BSB/raster,
   S57 vector and CM93 are unaffected.
3. **JCenter.** Shut down in 2021; removed to avoid resolution stalls.

It also repairs upstream layout drift: the app still refers to
`src/bitmaps/`, which the current core tree calls `resources/bitmaps/`.
This one matters — Gradle's `Copy` skips a missing source **silently**, so
leaving it yields an APK with no toolbar icons and no `styles.xml`, rather
than a build error.

## Upstream problems this pipeline works around

Found while getting the build to pass; all are handled automatically.

1. **arm64 is unbuildable with any current NDK.**
   `buildandroid/build_android.cmake` sets `CMAKE_AR` to
   `aarch64-linux-android-ar`, a triple-prefixed binutils wrapper Google removed
   in NDK r23+. armhf is unaffected because its branch already uses `llvm-ar`.
   OpenCPN CI builds only armhf, so nothing exercises this. Fixed by patching
   the toolchain file AND adding an NDK compat symlink -- the symlink is what
   rescues a build tree whose `link.txt` was already generated with the dead
   path, since cmake does not regenerate FetchContent sub-builds.

2. **`OCPN_BUILD_SAMPLE=ON` breaks the v5.14.x cross-build.** Upstream's armhf
   CI script passes it, but `plugins/demo_pi_sample` calls
   `find_package(wxWidgets)`, which searches for a HOST wxWidgets and fails the
   whole configure. Set to `OFF`; the APK does not use demo_pi.

3. **The app reads UI assets from a path the core no longer has.**
   `app/build.gradle` copies from `src/bitmaps/`, which the core tree calls
   `resources/bitmaps/`. Gradle's `Copy` SKIPS a missing source silently, so
   this produces an APK with no toolbar icons and no `styles.xml` rather than a
   build failure -- it looks like a clean build.

4. **The release build is broken as shipped.** `materialfilemanager`'s
   night theme extends `Theme.MaterialComponents.DayNight.DarkActionBar` and
   uses Material attrs, but the module depends only on the pre-AndroidX support
   library. Debug builds never notice; release runs `verifyReleaseResources`,
   fails resource linking, and no release APK can be produced. Fixed by adding
   the Material Components dependency the app module already uses.

5. **The status bar height is subtracted twice, leaving a black band above
   the navigation buttons.** `getDisplayMetrics` sends `height -
   statusBarHeight`, but outside fullscreen `height` is `dm.heightPixels`,
   which already excludes the status bar. The `m_fullScreen` branch adds it
   back before the same subtraction; the normal path does not. Native then
   sizes the canvas as `(height - statusBar) - actionBar`, so it comes out one
   status bar short and the window background shows through.

   Compounding it, `setupEdgeToEdge()` runs on EVERY Android version while the
   matching compensation (`actionBarHeight += getNavBarHeight()`) is gated to
   `SDK >= 35` -- so Android 13 gets edge-to-edge layout without the
   correction written for it.

   Fixed by mirroring the fullscreen correction. Verified on device: the black
   band is gone. On by default; `OPCN_FIX_STATUSBAR_DOUBLE=0` disables it.

6. **AGP leaves dead bytes in the APK.** Incremental packaging kept the previous
   run's entry data: after stripping, the rebuilt APK still measured 217 MB
   while containing only 81 MB of live entries. Valid (a zip is read from its
   trailing central directory) but 136 MB of waste. `05-apk.sh` therefore runs
   `clean assembleDebug`.

## Known gaps

- **Translations are missing.** `data/locale` no longer exists in the core tree
  (translations live in `po/` and need `msgfmt`), and wxWidgets' `wxstd.mo`
  files are not in the support bundle. The UI will be English. Cosmetic.
- **Version skew.** `OCPNAndroidCommon`'s last commit is 2023-09-02, while the
  app is 5.14.0 (March 2026). Upstream still links against these prebuilts, but
  a 2026 core linking against 2023 Qt libraries is the most likely place this
  build breaks.
- The APK is **debug-signed**. Installing it requires "install from unknown
  sources"; it will not upgrade a Play Store install in place.
- **Native libraries are stripped** by default, which is what brings the APK
  from 217 MB to 82 MB. Use `OPCN_KEEP_SYMBOLS=1` when debugging a native crash.
- **A rejected fix is kept behind a flag.** `OPCN_FIX_INSET_PADDING=1` removes
  the `v.setPadding(...)` in `setupEdgeToEdge()`. It was the first hypothesis
  for the black band and it made the band BIGGER -- the padding was masking an
  under-sized canvas, not causing it. **Off by default; do not enable it
  expecting a fix.** Kept only so the experiment is not repeated.

  The band itself is fixed by the status-bar correction (upstream defect 5).

## Licensing

OpenCPN is GPLv2+. Anything built here inherits that. This repository contains
only build scripts; it vendors no upstream code.
