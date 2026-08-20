#!/usr/bin/env bash
# Check the pins in env.sh against the rules in PINNING.md.
# Read-only: inspects the checkouts, changes nothing. Non-zero exit on failure.
set -uo pipefail
. "$(dirname "$0")/env.sh"

fail=0
note() { printf '  %-7s %s\n' "$1" "$2"; [ "$1" = FAIL ] && fail=1; return 0; }

echo ">>> Rule 1: core pin is a release-named commit"
if [ -d "$OCPN/.git" ]; then
  subject=$(git -C "$OCPN" log -1 --format='%s' "$OCPN_REF" 2>/dev/null)
  core_date=$(git -C "$OCPN" log -1 --format='%ad' --date=short "$OCPN_REF" 2>/dev/null)
  if printf '%s' "$subject" | grep -qiE '^Version [0-9]+\.[0-9]+'; then
    note OK "$OCPN_REF ($core_date) -- \"$subject\""
  else
    note FAIL "$OCPN_REF is not a release-named commit: \"$subject\""
  fi
else
  note SKIP "core checkout absent ($OCPN)"; core_date=""
fi

echo ">>> Rule 2: app and core carry the same version, close in time"
if [ -d "$APP/.git" ]; then
  app_date=$(git -C "$APP" log -1 --format='%ad' --date=short)
  app_ver=$(grep -oE 'versionName "[^"]+"' "$APP/app/build.gradle" | head -1 | cut -d'"' -f2)
  note INFO "app $app_ver, last commit $app_date"
  if [ -n "$core_date" ] && printf '%s' "$subject" | grep -q "$app_ver"; then
    note OK "core commit names the same version ($app_ver)"
  elif [ -n "$core_date" ]; then
    note FAIL "core commit \"$subject\" does not name the app version $app_ver"
  fi
else
  note SKIP "app checkout absent ($APP)"
fi

echo ">>> Rule 4: branch-fetched deps are pinned at or before the core date"
lun="$CACHE/lunasvg-$LUNASVG_REF"
if [ -d "$lun/.git" ]; then
  lun_date=$(git -C "$lun" log -1 --format='%ad' --date=short)
  if [ -z "$core_date" ]; then
    note SKIP "core date unknown; lunasvg is $lun_date"
  elif [ "$lun_date" \> "$core_date" ]; then
    note FAIL "lunasvg $LUNASVG_REF ($lun_date) is NEWER than the core release ($core_date)"
  else
    note OK "lunasvg $LUNASVG_REF ($lun_date) <= core release ($core_date)"
  fi
else
  note SKIP "lunasvg checkout absent ($lun)"
fi

# Upstream still declares GIT_TAG master; the pin above is what overrides it.
if [ -f "$OCPN/CMakeLists.txt" ] && grep -q 'GIT_TAG master' "$OCPN/CMakeLists.txt"; then
  note INFO "upstream still fetches lunasvg by branch; FETCHCONTENT_SOURCE_DIR_LUNASVG overrides it"
fi

echo
[ "$fail" -eq 0 ] && echo ">>> Pins OK" || echo ">>> PIN CHECK FAILED"
exit "$fail"
