# F-Droid repository

Serves the APKs built by this project's scripts, so an F-Droid client can
install and update them like any other app.

## What a user does

Add the repository URL in F-Droid (Settings -> Repositories -> +), together
with its fingerprint:

    https://ulyssehc.github.io/OpenCPN-Android-Unofficial/repo

The fingerprint is printed by `fdroid update` and must be published alongside
the URL — it is what stops a hostile mirror from serving different APKs. F-Droid
accepts it appended to the URL:

    https://ulyssehc.github.io/OpenCPN-Android-Unofficial/repo?fingerprint=<SHA256>

## Two different keys, both irreplaceable

Do not confuse them:

| Key | Signs | Lose it and... |
|---|---|---|
| **APK key** (`opencpn-release.jks`) | the app itself | users must uninstall to move to a new key, losing routes and settings |
| **Repo key** (`fdroid-keystore.p12`) | the repository index | every subscriber must remove and re-add the repo |

Neither belongs in git. Both are held as GitHub Actions secrets (below) and
should also exist in your own backup.

## First-time setup

1. Generate the repo signing key (once):

       fdroid init --keystore fdroid-keystore.p12 --repo-keyalias opcn

2. Add these repository secrets (Settings -> Secrets and variables -> Actions):

   - `FDROID_KEYSTORE_B64` — `base64 -w0 fdroid-keystore.p12`
   - `FDROID_KEYSTORE_PASS`
   - `FDROID_KEY_PASS`
   - `FDROID_KEY_ALIAS` — e.g. `opcn`

3. Set Pages to build from **GitHub Actions** (Settings -> Pages -> Source).

4. Publish a release with the APK attached, then run the **Publish F-Droid
   repo** workflow. It downloads the release assets, builds and signs the
   index, and deploys it to Pages.

## Why Pages is served from an Actions artifact

The workflow uploads the finished repository as a Pages artifact rather than
committing it to a branch. APKs are ~75 MB each; committing them would grow the
git history permanently, and force-pushing an orphan branch to avoid that is
easy to get wrong. Artifacts keep the git repository small and the published
site current.

Limits worth knowing: GitHub Pages allows 100 MB per file and about 1 GB per
site, with a soft bandwidth limit of 100 GB/month. `archive_older: 0` keeps only
current versions so the site does not creep past that.

## Honesty about what is published

The metadata declares the `NonFreeDep` anti-feature, because the build still
links Google Play Services (maps and location). It also states plainly that
this is an unofficial build, that the official app is sold on Google Play, and
what was removed. Do not quietly drop those notes: people installing from a
third-party repo deserve to know exactly what they are getting.
