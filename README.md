# OpenCPN for Android — unofficial builds

[OpenCPN](https://opencpn.org) is a free, open-source chart plotter and marine
navigation program. Its Android app is published only on Google Play, as a paid
app, with no APK download anywhere.

This project builds that app from the public GPL sources, and publishes the
result through an **F-Droid repository** so any Android device can install and
update it like a normal app.

> **Unofficial and unaffiliated.** These builds are not produced, reviewed or
> endorsed by the OpenCPN project. Please do not report problems with them to
> the OpenCPN developers — open an issue
> [here](https://github.com/ulyssehc/OpenCPN-Android-Unofficial/issues) instead.
>
> If you can, **buy the official app on Google Play**: it is the same software
> and it supports the people who write it.

Current build: **OpenCPN 5.14.0** (`versionCode` 128), arm64-v8a + armeabi-v7a,
Android 5.0+ (minSdk 21).

---

## Install

### With F-Droid (recommended)

[F-Droid](https://f-droid.org) is an open-source app store for Android. Adding
this repository to it gets you installs and updates automatically, the same way
you would get any other app.

1. Install the F-Droid client if you do not have it.
2. Open **Settings → Repositories → +** and add this URL, **fingerprint
   included**:

   ```
   https://ulyssehc.github.io/OpenCPN-Android-Unofficial/repo?fingerprint=253ccb6fdae9a21dadd3053b2287603036e74dc75c189105953826aca5311838
   ```

   Scanning the URL as a QR code, or opening it on the phone, works too.
3. Refresh, search for **OpenCPN**, install.

New versions published here then show up as ordinary F-Droid updates.

**Why the fingerprint matters.** A repository URL added *without* one trusts
whatever key answers that address. The fingerprint pins the key that signs the
repository index, so a hostile mirror cannot slip different APKs in. Everything
after `?fingerprint=` is that pin — keep it when you copy the URL.

That value is public, and it is checked on every publish: the workflow compares
the key it actually signed the index with against the fingerprint published in
`fdroid/README.md`, and fails the run if they differ.

### Or download the APK directly

Grab `opencpn-*.apk` from the
[releases page](https://github.com/ulyssehc/OpenCPN-Android-Unofficial/releases)
and install it. You will need to allow installs from unknown sources. There are
no automatic updates this way.

### Verifying what you installed

The app is signed with a key whose certificate fingerprint is committed in
[`expected-signing-cert.sha256`](expected-signing-cert.sha256):

```
SHA-256  0998a34afdc8a2ed182876e9f4b9ea079c057db3aea2d4ace8aca53443a7cee1
```

Check any downloaded APK against it with:

```
apksigner verify --print-certs opencpn-*.apk
```

Every release build is compared against that same value before it is published.

**Two different keys are involved, and confusing them is the usual way people
get this wrong:**

| | Signs | Where it is used |
|---|---|---|
| **App signing key** | the APK itself | Android ties updates to it — an APK signed with any other key will not install over this one |
| **F-Droid repo key** | the repository index, not the app | the `?fingerprint=` value you pin when adding the repository |

A certificate fingerprint is a public value in both cases. It identifies a key;
it cannot sign anything.

---

## Differences from the official build

This is the same source code, but it is not the same APK. Read this before
installing.

| | This build | Official Play build |
|---|---|---|
| Price | free | paid |
| o-charts (encrypted charts) | **not supported** | supported |
| Analytics / crash reporting | none | Firebase Analytics + Crashlytics |
| Signing key | personal key of this repository's owner | OpenCPN's |
| Support | none, and not from the OpenCPN project | from the developers you paid |
| Updates | F-Droid repository here | Play Store |

In detail:

- **o-charts encrypted charts will not work.** They need `oexserverd`, a binary
  from the proprietary o-charts plugin that is not publicly available, so it
  cannot be built or shipped. BSB/raster, S57 vector and CM93 charts are
  unaffected.
- **No analytics and no crash reporting.** Firebase Analytics and Crashlytics
  are stripped out. The app builds without them; the alternative would have been
  to ship analytics wired to a fabricated project.
- **It cannot update a Play Store install in place.** Android identifies an app
  by package *and signing key*. If you already have the paid app installed, this
  one will not install over it — the device rejects it as an invalid package,
  which looks a lot like a corrupted download. To switch you have to uninstall
  first, which loses local routes, waypoints and settings unless you export them
  beforehand. The same applies in reverse.
- **Four small UI icons are our own drawings.** The checkbox indicator and the
  two tab-bar scroll arrows are loaded from files that exist in none of the
  upstream repositories, so replacements were drawn for this build. Without
  them those controls render as empty boxes.
- **A few wxWidgets built-in strings stay English.** OpenCPN's own translations
  are built and shipped (7 languages, core plus all four bundled plugins), but
  wxWidgets' `wxstd.mo` catalogs are not available in the upstream support
  bundle.
- **Google Play Services (maps + location) are still linked in**, exactly as
  upstream links them. That is why the F-Droid metadata declares the
  `NonFreeDep` anti-feature rather than hiding it.

Nothing else is removed: the four bundled plugins (wmm, chartdldr, grib,
dashboard) are all present, for both ABIs.

Beyond that, eight defects in the upstream sources had to be worked around to
get a build that runs at all — including a canvas-height bug that leaves a black
band above the navigation buttons, and which almost certainly affects the Play
build too. They are documented in [BUILD.md](BUILD.md#upstream-defects-this-pipeline-works-around).

---

## Status

**Working.** The published build installs from the F-Droid repository and runs
correctly on Android 13 (/e/OS) and Android 17, on real hardware — charts, the
settings dialog, and the display geometry (no black band, nothing clipped at the
bottom). No known functional defects outstanding.

What the release APK contains, verified at build time:

```
org.opencpn.opencpn  versionCode 128  versionName 5.14.0
minSdk 21   targetSdk 36   native-code: arm64-v8a, armeabi-v7a
release: 75.3 MB, not debuggable, signed + zipaligned, signature pinned
```

Both `libgorp.so` cores (22.4 MB armv7a / 26.3 MB arm64, stripped), all 8 plugin
binaries (4 plugins × 2 ABIs), the Qt5 runtime libraries, 475 UI asset entries
and 7 translation catalogs.

The most likely place this breaks in future: upstream's prebuilt Qt5 bundle
(`OCPNAndroidCommon`) was last touched in 2023, while the app is from 2026.

---

## What is in this repository

Build scripts and packaging metadata — **no APK and no signing key**. Everything
here is public information: no keystore, no password, no secret.

| | |
|---|---|
| F-Droid repo | `https://ulyssehc.github.io/OpenCPN-Android-Unofficial/repo` |
| Releases | <https://github.com/ulyssehc/OpenCPN-Android-Unofficial/releases> |
| Package | `org.opencpn.opencpn` |
| Licence | GPLv2+, as OpenCPN itself |

| Path | What it is |
|---|---|
| [`BUILD.md`](BUILD.md) | how to build it yourself, and every patch applied |
| [`PINNING.md`](PINNING.md) | which upstream commits are used, and why those |
| `build.sh`, `scripts/` | the build pipeline |
| [`fdroid/`](fdroid/README.md) | F-Droid repository config, metadata, publishing setup |
| [`assets/styles/`](assets/styles/README.md) | the four replacement UI icons |
| `expected-signing-cert.sha256` | the pinned app-signing certificate fingerprint |

### Building it yourself

    OPCN_ROOT=~/opcn-build ./build.sh

Linux x86_64 and ~15 GB of free disk. See [BUILD.md](BUILD.md) for requirements, stages, release signing and the full list
of upstream problems the scripts work around.

---

## Who wrote this

**Everything in this repository was written by Claude Code (Anthropic's coding
agent), at the request of the repository owner.** The scripts, the patches, the
commit messages and this README are all agent-authored. Commits are attributed
to the owner as author with a `Co-Authored-By` trailer naming Claude.

The split of what was actually verified, and by whom, matters more than the
authorship:

- **The agent verified**: that the sources build; that the artifacts are real
  (file types, sizes, ABIs, APK contents, signature, alignment,
  non-debuggable); and that each patch applies and holds.
- **A human verified**: that the app installs from the F-Droid repository and
  runs on real phones (Android 13 / e OS, and Android 17), and that the canvas
  fills the screen on both. No device or emulator existed in the build
  environment, so nothing about runtime behaviour could be checked by the agent.

## Licensing

OpenCPN is GPLv2+, and anything built here inherits that. This repository
contains only build scripts and metadata; it vendors no upstream code.
