#!/usr/bin/env bash
# Cross-compile the OpenCPN core (libgorp.so) and the four bundled plugins
# for armeabi-v7a and arm64-v8a. Needs the NDK only -- no Gradle, no Maven.
set -euo pipefail
. "$(dirname "$0")/env.sh"

test -x "$TOOL_BASE/bin/clang" || { echo "FATAL: run 01-toolchain.sh first"; exit 1; }


# Upstream bug: the arm64 branch of buildandroid/build_android.cmake sets
# CMAKE_AR to aarch64-linux-android-ar, a triple-prefixed binutils wrapper
# Google REMOVED from the NDK in r23+. Only llvm-ar remains. armhf is
# unaffected because its branch already uses llvm-ar, which is why 32-bit
# builds and 64-bit fails at the first static-library link (plutovg).
# OpenCPN CI only builds armhf, so this path is untested upstream.
TC="$OCPN/buildandroid/build_android.cmake"
if grep -q 'bin/aarch64-linux-android-ar' "$TC"; then
  echo ">>> Patching CMAKE_AR: aarch64-linux-android-ar -> llvm-ar (NDK r23+)"
  sed -i 's|bin/aarch64-linux-android-ar|bin/llvm-ar|' "$TC"
fi

build() {  # build <tuple> <builddir>
  local tuple="$1" dir="$OCPN/$2"
  echo ">>> Building core: $tuple -> $2"
  mkdir -p "$dir"
  # Freshness marker. A failed configure leaves any PREVIOUS libgorp.so in
  # place, so "the file exists" is not evidence this run built anything --
  # it silently reports the last successful build's binary as this one's.
  touch "$dir/.build-stamp"
  # Give each build its own pristine copies: the build patches these source
  # trees in place, so a shared copy would be patched twice.
  local fc=()
  if [ "${OPCN_OFFLINE_DEPS:-0}" = "1" ]; then
    local shp="$dir/_shapelib_src" rj="$dir/_rapidjson_src"
    # REFRESH, do not merely create: the build applies patches to these trees
    # in place, so a second run would patch already-patched sources and fail
    # ("Failed to apply patch"). Copying pristine content over the top each
    # run is idempotent and needs no delete permission.
    mkdir -p "$shp" "$rj"
    cp -r "$CACHE/shapelib-v1.6.1/." "$shp/"
    cp -r "$CACHE/rapidjson-v1.1.0/." "$rj/"
    fc=(-DFETCHCONTENT_SOURCE_DIR_SHAPELIB_SRC="$shp"
        -DFETCHCONTENT_SOURCE_DIR_RAPIDJSON_SRC="$rj")
  else
    # Clear any cached override from a previous OPCN_OFFLINE_DEPS=1 run;
    # otherwise cmake keeps using the old (already patched) copies.
    fc=(-UFETCHCONTENT_SOURCE_DIR_SHAPELIB_SRC
        -UFETCHCONTENT_SOURCE_DIR_RAPIDJSON_SRC)
  fi
  ( cd "$dir"
    # OCPN_BUILD_SAMPLE is OFF deliberately. Upstream CI passes ON, but on
    # v5.14.x plugins/demo_pi_sample calls find_package(wxWidgets), which
    # searches for a HOST wxWidgets and fails the whole configure in a
    # cross-build. The APK does not use demo_pi -- gradle bundles only
    # wmm/chartdldr/grib/dashboard.
    cmake \
      -DCMAKE_BUILD_TYPE=Release \
      -DOCPN_TARGET_TUPLE:STRING="$tuple" \
      -DOCPN_BUILD_SAMPLE=OFF \
      -Dtool_base="$TOOL_BASE" \
      -DFETCHCONTENT_SOURCE_DIR_LUNASVG="$CACHE/lunasvg-$LUNASVG_REF" \
      "${fc[@]}" \
      ..
    # Upstream notes this explicit step is needed in CI; harmless otherwise.
    make lunasvg
    make -j"$(nproc)" )
}

# Tuple format is "<target>;<api>;<arch>", per CMakeLists.txt lines 52-53.
build "Android-armhf;16;armhf" "$BUILD_32"
build "Android-arm64;16;arm64" "$BUILD_64"

echo ">>> Core artifacts:"
fail=0
for d in "$BUILD_32" "$BUILD_64"; do
  lib="$OCPN/$d/libgorp.so"
  if [ ! -f "$lib" ]; then
    echo "    FAIL $d: libgorp.so not produced"; fail=1; continue
  fi
  if [ ! "$lib" -nt "$OCPN/$d/.build-stamp" ]; then
    echo "    FAIL $d: libgorp.so is STALE (older than this run)"; fail=1; continue
  fi
  echo "    OK   $lib ($(stat -c%s "$lib") bytes)"
  find "$OCPN/$d/plugins" -name 'lib*_pi.so' 2>/dev/null | sed 's/^/         /'
done
[ "$fail" -eq 0 ] || { echo ">>> CORE BUILD FAILED"; exit 1; }
