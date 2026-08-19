#!/usr/bin/env bash
# Host build dependencies. gettext is REQUIRED: the core cmake calls
# find_package(Gettext) and configure fails without msgfmt/msgmerge.
set -euo pipefail
PKGS="cmake git gettext curl unzip make"
if command -v apt-get >/dev/null; then
  sudo=""; [ "$(id -u)" -ne 0 ] && sudo="sudo"
  $sudo apt-get update -qq || true
  DEBIAN_FRONTEND=noninteractive $sudo apt-get install -y -qq $PKGS
else
  echo "Not a Debian/Ubuntu host -- ensure these are installed: $PKGS"
fi
for t in cmake git msgfmt msgmerge curl unzip; do
  command -v "$t" >/dev/null || { echo "FATAL: $t missing"; exit 1; }
done
echo ">>> Host dependencies OK"
