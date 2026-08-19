#!/usr/bin/env bash
# Install the Android SDK command line tools and the pinned NDK.
# Requires egress to dl.google.com.
set -euo pipefail
. "$(dirname "$0")/env.sh"

if [ ! -x "$SDK/cmdline-tools/latest/bin/sdkmanager" ]; then
  echo ">>> Installing Android command line tools"
  curl -fL -o "$CACHE/$CLI_TOOLS" "https://dl.google.com/android/repository/$CLI_TOOLS"
  mkdir -p "$SDK/cmdline-tools"
  rm -rf "$SDK/cmdline-tools/latest" "$SDK/cmdline-tools/cmdline-tools"
  unzip -q "$CACHE/$CLI_TOOLS" -d "$SDK/cmdline-tools"
  mv "$SDK/cmdline-tools/cmdline-tools" "$SDK/cmdline-tools/latest"
fi

echo ">>> Accepting licenses and installing SDK packages"
yes | "$SDK/cmdline-tools/latest/bin/sdkmanager" --licenses >/dev/null 2>&1 || true
"$SDK/cmdline-tools/latest/bin/sdkmanager" \
  "platform-tools" \
  "platforms;android-$COMPILE_SDK" \
  "build-tools;$BUILD_TOOLS" \
  "ndk;$NDK_VER"

test -x "$TOOL_BASE/bin/clang" \
  || { echo "FATAL: NDK toolchain missing at $TOOL_BASE"; exit 1; }

# NDK r23+ removed the triple-prefixed binutils wrappers, but OpenCPN's arm64
# toolchain file still calls aarch64-linux-android-ar. 03-core.sh patches that
# file; the symlink additionally repairs build trees whose link.txt was already
# generated with the dead path (cmake does not regenerate FetchContent
# sub-builds), so a resumed build recovers instead of needing a wipe.
if [ ! -e "$TOOL_BASE/bin/aarch64-linux-android-ar" ]; then
  ln -sf llvm-ar "$TOOL_BASE/bin/aarch64-linux-android-ar"
  echo ">>> Added NDK compat symlink: aarch64-linux-android-ar -> llvm-ar"
fi

echo ">>> Toolchain OK: $TOOL_BASE"
