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
echo ">>> Toolchain OK: $TOOL_BASE"
