# OpenCPN-Android-Unofficial — reproducible OpenCPN Android build

Scripts that build an OpenCPN APK (armeabi-v7a + arm64-v8a) from source, with
every upstream version pinned.

OpenCPN's official Android app is distributed only through Google Play, as a
paid app. There is no APK download. This repository builds one from the public
sources instead.

**Unofficial and unaffiliated.** Not produced, reviewed or endorsed by the
OpenCPN project. Please do not report problems with these builds to them.

## Repository

Everything below is public information. Nothing secret lives in this repository:
no keystore, no password, no APK.

| | |
|---|---|
| Repository | <https://github.com/ulyssehc/OpenCPN-Android-Unofficial> |
| Releases | <https://github.com/ulyssehc/OpenCPN-Android-Unofficial/releases> |
| F-Droid repo | `https://ulyssehc.github.io/OpenCPN-Android-Unofficial/repo` |
| Package | `org.opencpn.opencpn` |
| Upstream sources | OpenCPN core, OpenCPN-Android, OCPNAndroidCommon (see [Upstream pieces](#upstream-pieces)) |
| Licence | GPL, as OpenCPN itself (see [Licensing](#licensing)) |

### Fingerprints

Two different keys are involved, and confusing them is the usual way people get
this wrong.

**The APK signing key** identifies the app. Android ties updates to it: an APK
signed with any other key will not install over one signed with this one.

    SHA-256  0998a34afdc8a2ed182876e9f4b9ea079c057db3aea2d4ace8aca53443a7cee1

That value is committed in `expected-signing-cert.sha256` and every release
build is checked against it. Verify a downloaded APK yourself with:

    apksigner verify --print-certs opencpn-*.apk

**The F-Droid repository key** signs the index, not the app. It is printed in
the publish workflow's log rather than committed, because it is created on the
first publish. Pin it when adding the repository — a repo URL added without a
fingerprint trusts whatever key answers that URL:

    https://ulyssehc.github.io/OpenCPN-Android-Unofficial/repo?fingerprint=<SHA-256>

A certificate fingerprint is a public value in both cases. It identifies a key;
it cannot sign anything.

## Who wrote this

**Everything in this repository was written by Claude Code (Anthropic's coding
agent), in a single session, at the request of the repository owner.** The
scripts, the patches, the commit messages and this README are all agent-authored.
Commits are attributed to the owner as author with a `Co-Authored-By` trailer
naming Claude.

The split of what was actually verified, and by whom, matters more than the
authorship:

- **The agent verified**: that the sources build; that the artifacts are real
  (file types, sizes, ABIs, APK contents, signature, alignment, non-debuggable);
  and that each patch applies and holds.
- **A human verified**: that the app installs and runs on real phones
  (Android 13 / e OS, and Android 17), and that the canvas fills the screen on
  both -- no black band above the navigation buttons, nothing clipped at the
  bottom. No device or emulator existed in the build environment, so nothing
  about runtime behaviour could be checked by the agent.


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
on Android 13 (/e/OS) and Android 17, including the display-geometry fix below,
which is a different correction on either side of Android 15. No known
functional defects outstanding.

**This repository contains build scripts only** — no APK and no signing key.
Both are produced by running the scripts; the keystore is created on the first
release build and deliberately gitignored. Its certificate fingerprint is
committed, in `expected-signing-cert.sha256`, and that is a public value: it
identifies the key without being able to sign anything.

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
  consistent; it says nothing about *which* key signed it, so it passes
  happily on exactly the build you do not want.

The script also verifies the alignment and that the result is genuinely not
debuggable, rather than assuming either.
Configuration and pinned versions live in `scripts/env.sh`.

## Pinned versions

Which commits, and **why those commits**, is recorded in [PINNING.md](PINNING.md);
`scripts/07-check-pins.sh` enforces the rules. Read it before a version bump —
picking a branch tip instead of the release commit produces a build that works
well enough to fool you.

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

5. **The canvas is the wrong height, and it is wrong differently on either
   side of Android 15.** These are two distinct defects that look identical on
   screen -- a black band above the navigation buttons -- which is why the fix
   is gated by SDK level rather than applied uniformly.

   The chain is the same in both cases: `getDisplayMetrics` sends
   `height - statusBarHeight`, the native side subtracts `actionBarHeight`, and
   what is left becomes the canvas.

   **Below SDK 35, the status bar is subtracted twice.** Outside fullscreen
   `height` is `dm.heightPixels`, which already excludes the status bar, and
   the format string subtracts it again. The `m_fullScreen` branch adds it back
   before the same subtraction; the normal path does not. Compounding it,
   `setupEdgeToEdge()` runs on EVERY Android version while the compensation
   written for it (`actionBarHeight += getNavBarHeight()`) is gated to
   `SDK >= 35` -- so Android 13 gets edge-to-edge layout without the
   correction. Fixed by mirroring the fullscreen correction. **Confirmed by a
   controlled A/B test on one core**: with the patch the band is gone, with
   `OPCN_FIX_STATUSBAR_DOUBLE=0` it returns.

   **From SDK 35, the arithmetic uses the wrong quantities.** The window is
   edge-to-edge, so `dm.heightPixels` now INCLUDES the status bar and the
   pre-35 correction overshoots. Worse, the two values the chain subtracts do
   not describe the space actually taken: `statusBarHeight` is the legacy
   `status_bar_height` dimen, which a display cutout makes smaller than the
   real top inset, and `actionBarHeight` already carries `getNavBarHeight()`.
   Two corrections derived from those numbers were built and tested on
   Android 17 -- one left the canvas too tall and clipped the SOG/COG bar, the
   other too short and reopened the black band. **The fix stops computing and
   measures**: `setupEdgeToEdge()` pads `android.R.id.content` with the real
   insets, so that view's height minus its own padding IS the area available to
   the Qt surface, whatever the cutout, action bar or navigation mode turn out
   to be. Sending that plus the two quantities the chain subtracts makes the
   canvas come out equal to it. The content view is read rather than a
   Qt-owned one because `androidForceFullRepaint()` resizes the frame by 1 px
   before re-querying, which would ratchet the canvas smaller on every repaint.

   Both on by default; the pre-35 branch is untouched by the SDK 35+ work.

6. **Four style icons are published nowhere.** `androidUTIL.cpp` loads
   `<SharedDataDir>/styles/{chek_full,chek_empty,tabbar_button_left,
   tabbar_button_right}.png` and injects them into Qt stylesheets as the
   checkbox indicator and the tab-bar scroll arrows. They exist in NONE of the
   upstream repositories -- the core's `data/styles/` holds only
   `qtstylesheet.qss`. Anyone building from public sources gets an empty box
   where each checkbox and tab arrow should be, and the only trace is four
   `can't open file` lines in `opencpn.log`.

   Unlike the others this cannot be fixed by pinning or patching, because the
   assets do not exist. `assets/styles/` therefore holds **our own drawings**;
   `04-patch-app.sh` installs them into the core tree before packaging.

7. **Translations are compiled, then excluded from the Android build.**
   `CMakeLists.txt` defines an `i18n` target and then wires it in for every
   platform except this one:

       add_custom_target(i18n ... DEPENDS ${_gmoFiles})
       if (NOT QT_ANDROID)
         add_dependencies(${PACKAGE_NAME} i18n)
       endif ()

   So the catalogs are never built, gradle's `copyLocale*` tasks find nothing,
   and -- `Copy` skipping missing sources silently again -- the app ships
   untranslated with no error anywhere. `03-core.sh` runs `make i18n`, which
   puts `Resources/opencpn_<lang>.lproj/opencpn.mo` exactly where gradle looks.
   Verified on device: 7 languages, core plus all four plugin catalogs.

8. **AGP leaves dead bytes in the APK.** Incremental packaging kept the previous
   run's entry data: after stripping, the rebuilt APK still measured 217 MB
   while containing only 81 MB of live entries. Valid (a zip is read from its
   trailing central directory) but 136 MB of waste. `05-apk.sh` therefore runs
   `clean assembleDebug`.

## Worth reporting upstream

Four of the six defects below are not specific to this build setup -- they are
in the upstream sources and affect anyone building or, in one case, running the
official app:

- **Defect 5 (canvas height)** most likely affects the **Google Play build
  too**, on both sides of Android 15. The code path is identical and nothing in
  this pipeline introduced it: `setupEdgeToEdge()` runs on every Android
  version while the compensation written for it is gated to `SDK >= 35`, and
  above 35 the compensation is built from the legacy `status_bar_height` dimen,
  which is not the inset the window is actually padded by.
- **Defect 1 (arm64 `CMAKE_AR`)** makes arm64 unbuildable with any NDK from
  r23 onward. Upstream CI builds armhf only, so nothing exercises it.
- **Defect 4 (`materialfilemanager`)** makes `assembleRelease` fail outright,
  so the release path is broken as shipped.
- **Defect 3 (`src/bitmaps` vs `resources/bitmaps`)** silently produces an APK
  with no toolbar icons, because Gradle's `Copy` skips missing sources without
  failing.

These have not been reported upstream. Anyone is welcome to; the analysis and
the one-line patches are in `scripts/04-patch-app.sh` and `scripts/03-core.sh`.

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
## Licensing

OpenCPN is GPLv2+. Anything built here inherits that. This repository contains
only build scripts; it vendors no upstream code.
