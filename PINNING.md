# How versions are chosen

Every version here is pinned to a specific commit or tag, and this file records
which rule produced each one. It exists because getting this wrong does not look
like a build failure — it looks like a working app with a dead button.

## The failure this prevents

The first working build paired the **released** Android front end (versionCode
128, app repo last touched 2026-03-29) with a core from the **branch tip**
(2026-08-13) — four months of post-release development the front end had never
been compiled against. The result built cleanly, installed, ran, and charted.
It also had a "Add chart directory" button that did nothing, because the
file-dialog code changed in between.

Nothing in the build could have caught that. Only a person tapping the button.

## Rules

1. **Anchor on the commit that names the release, never a branch tip.**
   A branch tip is post-release development by definition.

       git log --oneline v5.14.x | grep -iE 'Version [0-9]+\.[0-9]+\.[0-9]+'

2. **Pair the core with the app commit carrying the same version.**
   The two repositories are not coordinated, so the app is the constraint: find
   the app commit whose `versionName`/`versionCode` you are building, and take
   the core release bearing that same version. They should be days apart, not
   months. A core commit months newer than the app is the smell.

3. **Prefer the date the app itself reports, when it is available.**
   `CMakeLists.txt` stamps `VERSION_DATE` into the build and OpenCPN shows it in
   About. If a known-good build is installed, its About screen dates the core to
   the day; take the last core commit at or before that date. Note that the git
   hash is NOT embedded — `cmake/version_git.cmake` only feeds source tarballs —
   so About is as precise as an artifact gets.

4. **Pin anything fetched by branch, because rule 1 cannot save you.**
   Upstream fetches lunasvg with `GIT_TAG master`. No choice of OpenCPN commit
   makes that reproducible: the renderer changes under you with the calendar.
   Pin such dependencies to a commit at or before the core's release date.

5. **When in doubt, ask upstream.** One question — "which core commit did
   5.14.0 build from?" — beats every inference above and costs nothing.

## Applied to the current pins

| Pin | Value | Rule | Evidence |
|---|---|---|---|
| OpenCPN core | `91f3b674` | 1 | commit subject is literally `Version 5.14.0`, 2026-04-07 |
| App front end | `1308082` | 2 | `versionCode 128` / `versionName "5.14.0"`, 2026-03-29 — 9 days before the core release, consistent with a release sequence |
| lunasvg | `b350c01` | 4 | 2026-02-05, the last commit before the core release; upstream would otherwise take whatever `master` is today |
| Android NDK | `26.1.10909125` | — | the version OpenCPN CI itself pins |
| shapelib | `v1.6.1` | — | the tag upstream's own `URL_HASH` pins |
| rapidjson | `v1.1.0` | — | the tag upstream's own `URL_HASH` pins |
| Gradle / AGP / SDK | 8.11.1 / 8.9.1 / 35 | — | read from the app repo's own gradle files |

`scripts/07-check-pins.sh` re-checks rules 1, 2 and 4 against the checkouts.

## At the next version bump

1. Find the app commit for the new `versionCode`; note its date and version.
2. Find the core commit named `Version <same version>`; confirm the dates are
   close.
3. Move the lunasvg pin to the last commit at or before that core date.
4. Update `scripts/env.sh`, run `scripts/07-check-pins.sh`, rebuild.
5. Install and **use** the result — open the settings dialog, tap the buttons.
   The failures this file is about are invisible to the build.

## What this still does not give you

Reproducibility is not verification. Matching commits makes a build consistent;
it does not prove it behaves like the official one. The mechanical check would
be an artifact-level diff — packaged asset inventory, exported symbols — against
a known-good APK. That needs a reference APK, which this project does not have,
so "install it and use it" remains the last step.
