#!/usr/bin/env bash
# Shared configuration. Versions are pinned so the APK is reproducible.
set -euo pipefail

# Pinned versions -------------------------------------------------------------
NDK_VER="26.1.10909125"        # pinned by OpenCPN CI (ci/circleci-build-android-corelib-armhf.sh)
COMPILE_SDK="35"               # OpenCPN-Android app/build.gradle: compileSdkVersion
BUILD_TOOLS="34.0.0"           # OpenCPN-Android app/build.gradle: buildToolsVersion
CLI_TOOLS="commandlinetools-linux-11076708_latest.zip"

# Upstream sources ------------------------------------------------------------
OCPN_REPO="https://github.com/OpenCPN/OpenCPN"              # core, builds libgorp.so + plugins
# Build the STABLE maintenance branch matching the app's 5.14.0 front end, not
# master. Pairing a released Java app with dev-HEAD native code invites subtle
# runtime skew. Pinned to a commit so the build is reproducible: master moves
# daily and a branch name alone is not a version.
OCPN_REF="91f3b674"                                          # "Version 5.14.0", 2026-04-07
OCPN_BRANCH="v5.14.x"

# Upstream fetches lunasvg with GIT_TAG master -- an unpinned moving branch, so
# the renderer you get depends on the day you build. Pin it to the last commit
# before the 5.14.0 release so icons render as the release intended.
LUNASVG_REF="b350c01"                                        # 2026-02-05
APP_REPO="https://github.com/bdbcat/OpenCPN-Android"        # the Gradle app (5.14.0 / vc 128)
COMMON_REPO="https://github.com/bdbcat/OCPNAndroidCommon"   # prebuilt Qt5 + wxQt (895 MB)

# Layout ----------------------------------------------------------------------
ROOT="${OPCN_ROOT:-$HOME/opcn-build}"
SDK="${ANDROID_SDK_ROOT:-$ROOT/android-sdk}"
CACHE="$ROOT/cache"
OCPN="$ROOT/opencpn"
APP="$ROOT/OpenCPN-Android"
COMMON="$ROOT/OCPNAndroidCommon"
TOOL_BASE="$SDK/ndk/$NDK_VER/toolchains/llvm/prebuilt/linux-x86_64"

# Build directory names are NOT arbitrary: app/build.gradle refers to them by
# name (OCPN_Build / OCPN_Build_64), so keeping them means patching two lines
# instead of a dozen.
BUILD_32="build_android_32_cci_22b"
BUILD_64="build_android_64_cci_22b"

export ANDROID_SDK_ROOT="$SDK"
mkdir -p "$ROOT" "$CACHE"
