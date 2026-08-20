# Building it yourself

Everything about compiling OpenCPN for Android from source lives here. If you
only want to install the app, you do not need this file — see the
[README](README.md).

The pipeline builds an APK for `armeabi-v7a` + `arm64-v8a` from the public
OpenCPN sources, with every upstream version pinned. It is a stack of shell
scripts; there is no magic and no vendored upstream code.

- [Requirements](#requirements)
- [Running the build](#running-the-build)
- [Signed release builds](#signed-release-builds)
- [Pinned versions](#pinned-versions)
- [Upstream pieces](#upstream-pieces)
- [What the patches remove](#what-the-patches-remove)
- [Upstream defects this pipeline works around](#upstream-defects-this-pipeline-works-around)
- [Worth reporting upstream](#worth-reporting-upstream)
- [Build-side gaps](#build-side-gaps)
- [Publishing to the F-Droid repo](#publishing-to-the-f-droid-repo)

## Requirements

- Linux x86_64, JDK 17+, cmake, make, git, curl, unzip, **gettext**
  (`scripts/00-hostdeps.sh` installs these; gettext is not optional — the core
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

## Running the build

    OPCN_ROOT=~/opcn-build ./build.sh

    # where GitHub archive downloads are blocked (see Requirements):
    OPCN_ROOT=~/opcn-build OPCN_OFFLINE_DEPS=1 ./build.sh

`build.sh` just runs the stages in order. Any of them can be run alone, against
the same `OPCN_ROOT`:

| Script | Does |
|---|---|
| `scripts/00-hostdeps.sh` | installs host packages |
| `scripts/01-toolchain.sh` | SDK cmdline-tools, NDK, build-tools |
| `scripts/02-sources.sh` | clones the four upstream repositories at their pins |
| `scripts/03-core.sh` | builds `libgorp.so` + plugins for both ABIs, and `make i18n` |
| `scripts/04-patch-app.sh` | patches the Gradle app, installs the style icons |
| `scripts/05-apk.sh` | `clean assembleDebug` |
| `scripts/06-release.sh` | signed, zipaligned, non-debuggable APK |
| `scripts/07-check-pins.sh` | re-checks the pinning rules against the checkouts |

Configuration and pinned versions live in `scripts/env.sh`.

Two flags worth knowing:

- `OPCN_KEEP_SYMBOLS=1` — skip stripping the native libraries. This is what
  takes the APK from ~82 MB to ~217 MB, so use it only when debugging a native
  crash.
- `OPCN_FIX_STATUSBAR_DOUBLE=0` — disable the pre-Android-15 canvas-height fix
  (defect 5 below). Present so the fix can be A/B tested on a device.

## Signed release builds

    scripts/06-release.sh

It reads `$OPCN_ROOT/opencpn-release.jks` (with the password beside it) or
`OPCN_KEYSTORE` / `OPCN_KS_PASS` / `OPCN_KS_ALIAS`. **Back that keystore up and
keep it out of git.** Android ties updates to the signing key: build with a
different key and the APK will not install as an update at all — the device
rejects it as an invalid package, which is easy to mistake for a corrupted
download.

Because that failure is silent at build time, two guards sit in the way:

- **A missing keystore is fatal.** Creating the first one requires
  `OPCN_KS_GENERATE=1`. Generating a key whenever none is found is how a fresh
  container produces an APK nobody can install — it happened, and cost a build
  cycle.
- **The signing certificate is pinned** in `expected-signing-cert.sha256` and
  compared after signing. `apksigner verify` only proves an APK is internally
  consistent; it says nothing about *which* key signed it, so it passes happily
  on exactly the build you do not want.

The script also verifies the alignment and that the result is genuinely not
debuggable, rather than assuming either.

The keystore is created on the first release build and is deliberately
gitignored. Only its certificate fingerprint is committed — a public value that
identifies the key without being able to sign anything.

## Pinned versions

Which commits, and **why those commits**, is recorded in [PINNING.md](PINNING.md);
`scripts/07-check-pins.sh` enforces the rules. Read it before a version bump —
picking a branch tip instead of the release commit produces a build that works
well enough to fool you.

| Component | Version | Source |
|---|---|---|
| OpenCPN core | v5.14.x @ `91f3b674` (2026-04-07) | commit named `Version 5.14.0` |
| App front end | `1308082` (versionCode 128, 2026-03-29) | `bdbcat/OpenCPN-Android` |
| lunasvg | `b350c01` (2026-02-05) | upstream fetches `master`; pinned here |
| Android NDK | 26.1.10909125 | pinned by OpenCPN CI |
| SDK cmdline-tools | 11076708 | |
| compileSdk / buildTools | 35 / 34.0.0 | `OpenCPN-Android/app/build.gradle` |
| Gradle / AGP | 8.11.1 / 8.9.1 | upstream wrapper |

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

## What the patches remove

`scripts/04-patch-app.sh` removes things that cannot be built outside the
upstream maintainer's own machine. Each is a decision, not an oversight; the
user-visible consequences are summarised in the README's
[Differences from the official build](README.md#differences-from-the-official-build).

1. **Firebase / Crashlytics / Analytics.** The app applies
   `com.google.gms.google-services` but ships no `google-services.json`, so the
   plugin hard-fails. Removing the plugin and dependencies is not sufficient:
   `QtActivity.java` also USES `FirebaseAnalytics` (import, field, and a
   `getInstance` call whose result is never read again), so the patch strips
   those four references too and asserts none remain. The alternative — a
   fabricated `google-services.json` — would build, but ship analytics wired to
   a bogus project.
2. **`oexserverd`.** Copied from the proprietary o-charts plugin, which is not
   public. Dropped, so o-charts encrypted charts will not work. BSB/raster,
   S57 vector and CM93 are unaffected.
3. **JCenter.** Shut down in 2021; removed to avoid resolution stalls.

It also repairs upstream layout drift: the app still refers to `src/bitmaps/`,
which the current core tree calls `resources/bitmaps/`. This one matters —
Gradle's `Copy` skips a missing source **silently**, so leaving it yields an APK
with no toolbar icons and no `styles.xml`, rather than a build error.

## Upstream defects this pipeline works around

Found while getting the build to pass; all are handled automatically.

1. **arm64 is unbuildable with any current NDK.**
   `buildandroid/build_android.cmake` sets `CMAKE_AR` to
   `aarch64-linux-android-ar`, a triple-prefixed binutils wrapper Google removed
   in NDK r23+. armhf is unaffected because its branch already uses `llvm-ar`.
   OpenCPN CI builds only armhf, so nothing exercises this. Fixed by patching
   the toolchain file AND adding an NDK compat symlink — the symlink is what
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
   build failure — it looks like a clean build.

4. **The release build is broken as shipped.** `materialfilemanager`'s night
   theme extends `Theme.MaterialComponents.DayNight.DarkActionBar` and uses
   Material attrs, but the module depends only on the pre-AndroidX support
   library. Debug builds never notice; release runs `verifyReleaseResources`,
   fails resource linking, and no release APK can be produced. Fixed by adding
   the Material Components dependency the app module already uses.

5. **The canvas is the wrong height, and it is wrong differently on either side
   of Android 15.** These are two distinct defects that look identical on
   screen — a black band above the navigation buttons — which is why the fix is
   gated by SDK level rather than applied uniformly.

   The chain is the same in both cases: `getDisplayMetrics` sends
   `height - statusBarHeight`, the native side subtracts `actionBarHeight`, and
   what is left becomes the canvas.

   **Below SDK 35, the status bar is subtracted twice.** Outside fullscreen
   `height` is `dm.heightPixels`, which already excludes the status bar, and the
   format string subtracts it again. The `m_fullScreen` branch adds it back
   before the same subtraction; the normal path does not. Compounding it,
   `setupEdgeToEdge()` runs on EVERY Android version while the compensation
   written for it (`actionBarHeight += getNavBarHeight()`) is gated to
   `SDK >= 35` — so Android 13 gets edge-to-edge layout without the correction.
   Fixed by mirroring the fullscreen correction. **Confirmed by a controlled A/B
   test on one core**: with the patch the band is gone, with
   `OPCN_FIX_STATUSBAR_DOUBLE=0` it returns.

   **From SDK 35, the arithmetic uses the wrong quantities.** The window is
   edge-to-edge, so `dm.heightPixels` now INCLUDES the status bar and the pre-35
   correction overshoots. Worse, the two values the chain subtracts do not
   describe the space actually taken: `statusBarHeight` is the legacy
   `status_bar_height` dimen, which a display cutout makes smaller than the real
   top inset, and `actionBarHeight` already carries `getNavBarHeight()`. Two
   corrections derived from those numbers were built and tested on Android 17 —
   one left the canvas too tall and clipped the SOG/COG bar, the other too short
   and reopened the black band. **The fix stops computing and measures**:
   `setupEdgeToEdge()` pads `android.R.id.content` with the real insets, so that
   view's height minus its own padding IS the area available to the Qt surface,
   whatever the cutout, action bar or navigation mode turn out to be. Sending
   that plus the two quantities the chain subtracts makes the canvas come out
   equal to it. The content view is read rather than a Qt-owned one because
   `androidForceFullRepaint()` resizes the frame by 1 px before re-querying,
   which would ratchet the canvas smaller on every repaint.

   Both on by default; the pre-35 branch is untouched by the SDK 35+ work.

6. **Four style icons are published nowhere.** `androidUTIL.cpp` loads
   `<SharedDataDir>/styles/{chek_full,chek_empty,tabbar_button_left,
   tabbar_button_right}.png` and injects them into Qt stylesheets as the
   checkbox indicator and the tab-bar scroll arrows. They exist in NONE of the
   upstream repositories — the core's `data/styles/` holds only
   `qtstylesheet.qss`. Anyone building from public sources gets an empty box
   where each checkbox and tab arrow should be, and the only trace is four
   `can't open file` lines in `opencpn.log`.

   Unlike the others this cannot be fixed by pinning or patching, because the
   assets do not exist. `assets/styles/` therefore holds **our own drawings**
   (see [assets/styles/README.md](assets/styles/README.md)); `04-patch-app.sh`
   installs them into the core tree before packaging.

7. **Translations are compiled, then excluded from the Android build.**
   `CMakeLists.txt` defines an `i18n` target and then wires it in for every
   platform except this one:

       add_custom_target(i18n ... DEPENDS ${_gmoFiles})
       if (NOT QT_ANDROID)
         add_dependencies(${PACKAGE_NAME} i18n)
       endif ()

   So the catalogs are never built, gradle's `copyLocale*` tasks find nothing,
   and — `Copy` skipping missing sources silently again — the app ships
   untranslated with no error anywhere. `03-core.sh` runs `make i18n`, which
   puts `Resources/opencpn_<lang>.lproj/opencpn.mo` exactly where gradle looks.
   Verified on device: 7 languages, core plus all four plugin catalogs.

8. **AGP leaves dead bytes in the APK.** Incremental packaging kept the previous
   run's entry data: after stripping, the rebuilt APK still measured 217 MB
   while containing only 81 MB of live entries. Valid (a zip is read from its
   trailing central directory) but 136 MB of waste. `05-apk.sh` therefore runs
   `clean assembleDebug`.

## Worth reporting upstream

Four of the defects above are not specific to this build setup — they are in the
upstream sources and affect anyone building or, in one case, running the
official app:

- **Defect 5 (canvas height)** most likely affects the **Google Play build
  too**, on both sides of Android 15. The code path is identical and nothing in
  this pipeline introduced it: `setupEdgeToEdge()` runs on every Android version
  while the compensation written for it is gated to `SDK >= 35`, and above 35
  the compensation is built from the legacy `status_bar_height` dimen, which is
  not the inset the window is actually padded by.
- **Defect 1 (arm64 `CMAKE_AR`)** makes arm64 unbuildable with any NDK from r23
  onward. Upstream CI builds armhf only, so nothing exercises it.
- **Defect 4 (`materialfilemanager`)** makes `assembleRelease` fail outright, so
  the release path is broken as shipped.
- **Defect 3 (`src/bitmaps` vs `resources/bitmaps`)** silently produces an APK
  with no toolbar icons, because Gradle's `Copy` skips missing sources without
  failing.

These have not been reported upstream. Anyone is welcome to; the analysis and
the one-line patches are in `scripts/04-patch-app.sh` and `scripts/03-core.sh`.

## Build-side gaps

- **Version skew.** `OCPNAndroidCommon`'s last commit is 2023-09-02, while the
  app is 5.14.0 (March 2026). Upstream still links against these prebuilts, but
  a 2026 core linking against 2023 Qt libraries is the most likely place this
  build breaks.
- **wxWidgets' own catalogs are missing.** OpenCPN's translations are built
  (defect 7), but `wxstd.mo` is not in the support bundle, so a handful of
  wx built-in strings stay English.
- **Reproducibility is not verification.** Matching commits makes a build
  consistent; it does not prove it behaves like the official one. See the last
  section of [PINNING.md](PINNING.md).

## Publishing to the F-Droid repo

The APK is distributed through a self-hosted F-Droid repository served from
GitHub Pages. Everything a maintainer needs — the two signing keys, the Actions
secrets, why Pages is served from an artifact — is in
[fdroid/README.md](fdroid/README.md). The workflow itself is
`.github/workflows/fdroid.yml`, and it is manual (`workflow_dispatch`): publish
a GitHub release with the APK attached, then run **Publish F-Droid repo**.
