#!/usr/bin/env bash
# Cross-compile the OpenCPN core (libgorp.so) and the four bundled plugins
# for armeabi-v7a and arm64-v8a. Needs the NDK only -- no Gradle, no Maven.
set -euo pipefail
. "$(dirname "$0")/env.sh"

test -x "$TOOL_BASE/bin/clang" || { echo "FATAL: run 01-toolchain.sh first"; exit 1; }

build() {  # build <tuple> <builddir>
  local tuple="$1" dir="$OCPN/$2"
  echo ">>> Building core: $tuple -> $2"
  mkdir -p "$dir"
  ( cd "$dir"
    cmake \
      -DCMAKE_BUILD_TYPE=Release \
      -DOCPN_TARGET_TUPLE:STRING="$tuple" \
      -DOCPN_BUILD_SAMPLE=ON \
      -Dtool_base="$TOOL_BASE" \
      ..
    # Upstream notes this explicit step is needed in CI; harmless otherwise.
    make lunasvg
    make -j"$(nproc)" )
}

# Tuple format is "<target>;<api>;<arch>", per CMakeLists.txt lines 52-53.
build "Android-armhf;16;armhf" "$BUILD_32"
build "Android-arm64;16;arm64" "$BUILD_64"

echo ">>> Core artifacts:"
for d in "$BUILD_32" "$BUILD_64"; do
  find "$OCPN/$d" -name 'libgorp.so' -o -name 'lib*_pi.so' | sed 's/^/    /'
done
