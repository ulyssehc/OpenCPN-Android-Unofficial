# opcn — reproducible OpenCPN Android build

Scripts that build an OpenCPN APK (armeabi-v7a + arm64-v8a) from source, with
every upstream version pinned.

OpenCPN's official Android app is distributed only through Google Play, as a
paid app. There is no APK download. This repository builds one from the public
sources instead.

## Status

**The scripts have not produced an APK yet.** They were written and partially
verified in an environment whose egress policy blocks `dl.google.com`, so the
Android SDK and NDK could never be downloaded.

What IS verified, against real checkouts:

- All three upstream repositories clone, and the prebuilt libraries in
  `OCPNAndroidCommon` are real files, not Git LFS stubs (895 MB: 125 arm64 and
  141 armv7a Qt5 `.so`, plus wxQt for both ABIs).
- `OCPNAndroidCoreBuildSupport.zip` (326 MB) downloads and extracts, providing
  prebuilt wxWidgets and OpenSSL for the core build (1.3 GB extracted).
- `scripts/04-patch-app.sh` applies cleanly, and after it **117 of the app's
  asset sources resolve**; the only ones left missing are translations (below).

What is NOT verified: the compile and link steps, and therefore whether the
resulting APK runs. Treat step 3 and step 5 as untested.

## Requirements

- Linux x86_64, JDK 17+, cmake, ninja/make, git, curl, unzip
- ~15 GB free disk
- Network access to:
  - `dl.google.com` and `maven.google.com` — SDK, NDK, Android Gradle Plugin,
    AndroidX. `maven.google.com` 301-redirects to `dl.google.com`, so **both**
    must be allowed or artifact resolution fails at the redirect.
  - `github.com` / `objects.githubusercontent.com` — sources and support bundle
  - `repo1.maven.org`, `plugins.gradle.org`, `services.gradle.org`

Qt's and OpenCPN's own download servers are NOT needed: every native
prerequisite comes from GitHub.

## Usage

    OPCN_ROOT=~/opcn-build ./build.sh

Or one stage at a time — `scripts/01-toolchain.sh` … `scripts/05-apk.sh`.
Configuration and pinned versions live in `scripts/env.sh`.

## Pinned versions

| Component | Version | Source |
|---|---|---|
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

1. **Firebase / Crashlytics.** The app applies `com.google.gms.google-services`
   but ships no `google-services.json`, so the plugin hard-fails. Removed
   rather than fabricating a Firebase config. No crash reporting.
2. **`oexserverd`.** Copied from the proprietary o-charts plugin, which is not
   public. Dropped, so **o-charts encrypted charts will not work**. BSB/raster,
   S57 vector and CM93 are unaffected.
3. **JCenter.** Shut down in 2021; removed to avoid resolution stalls.

It also repairs upstream layout drift: the app still refers to
`src/bitmaps/`, which the current core tree calls `resources/bitmaps/`.
This one matters — Gradle's `Copy` skips a missing source **silently**, so
leaving it yields an APK with no toolbar icons and no `styles.xml`, rather
than a build error.

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

## Licensing

OpenCPN is GPLv2+. Anything built here inherits that. This repository contains
only build scripts; it vendors no upstream code.
