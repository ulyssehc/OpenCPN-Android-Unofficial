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

# The core is pinned to a commit on the stable branch; the other two track
# their default branches (they are the app and its prebuilt libraries).
if [ -d "$OCPN/.git" ]; then
  echo ">>> opencpn already present"
else
  echo ">>> Cloning opencpn at $OCPN_BRANCH"
  git clone --depth 1 --branch "$OCPN_BRANCH" "$OCPN_REPO" "$OCPN"
  ( cd "$OCPN" && git fetch --depth 1 origin "$OCPN_REF" && git checkout -q "$OCPN_REF" )
fi
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

# Two cmake dependencies are fetched as GitHub *archive tarballs*
# (codeload.github.com), which some egress policies block while plain git
# clone is allowed. Pre-populating them from git skips those downloads.
# The others (spdlog, googletest, nlohmann/json) use git or release assets
# and need no help.
# Off by default: upstream verifies these tarballs with URL_HASH, and
# FETCHCONTENT_SOURCE_DIR bypasses that check, so a git tag becomes the
# integrity anchor instead of a sha256. Only worth it when codeload is blocked.
if [ "${OPCN_OFFLINE_DEPS:-0}" = "1" ]; then
  for spec in "shapelib:https://github.com/OSGeo/shapelib:v1.6.1" \
              "rapidjson:https://github.com/Tencent/rapidjson:v1.1.0"; do
    name="${spec%%:*}"; rest="${spec#*:}"; url="${rest%:*}"; tag="${rest##*:}"
    if [ ! -d "$CACHE/$name-$tag" ]; then
      echo ">>> Fetching $name $tag (OPCN_OFFLINE_DEPS)"
      git clone -q --depth 1 --branch "$tag" "$url" "$CACHE/$name-$tag"
    fi
  done
fi

echo ">>> Sources OK"
