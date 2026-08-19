#!/usr/bin/env bash
# Build OpenCPN for Android end to end.
#   OPCN_ROOT=/path/to/workdir ./build.sh
set -euo pipefail
cd "$(dirname "$0")"
for s in 00-hostdeps 01-toolchain 02-sources 03-core 04-patch-app 05-apk; do
  echo; echo "=============== $s ==============="
  bash "scripts/$s.sh"
done
