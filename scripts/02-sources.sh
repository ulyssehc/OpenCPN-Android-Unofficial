#!/usr/bin/env bash
# Clone the three upstream repositories. No Google egress needed.
set -euo pipefail
. "$(dirname "$0")/env.sh"

clone() {  # clone <url> <dir>
  if [ -d "$2/.git" ]; then
    echo ">>> $(basename "$2") already present"
  else
    echo ">>> Cloning $(basename "$2")"
    GIT_LFS_SKIP_SMUDGE=1 git clone --depth 1 "$1" "$2"
  fi
}

clone "$OCPN_REPO"   "$OCPN"
clone "$APP_REPO"    "$APP"
clone "$COMMON_REPO" "$COMMON"

# The core build downloads this at cmake configure time; pre-fetching it makes
# the configure step offline and lets us fail early if GitHub is unreachable.
mkdir -p "$OCPN/cache"
if [ ! -d "$OCPN/cache/OCPNAndroidCoreBuildSupport" ]; then
  echo ">>> Fetching OCPNAndroidCoreBuildSupport (326 MB, prebuilt wxQt for the core)"
  curl -fL -o "$OCPN/cache/support.zip" \
    "https://github.com/bdbcat/OCPNAndroidCoreBuildSupport/releases/download/v1.2/OCPNAndroidCoreBuildSupport.zip"
  ( cd "$OCPN/cache" && cmake -E tar -xzf support.zip )
fi
echo ">>> Sources OK"
