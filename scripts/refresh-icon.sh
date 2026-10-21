#!/usr/bin/env bash
# refresh-icon.sh - make macOS show Snotify.app's current icon on its banners.
#
# Usage: scripts/refresh-icon.sh [APP]      (default ~/Applications/Snotify.app; or: just refresh-icon)
#
# Found on 2026-10-17: a reinstall does not change the icon on a banner. The
# installed bundle carried the slime icon and the banners still showed the
# bell from the first build under this bundle id, because Notification Center
# and the icon service remember the first icon they saw for an id. Nothing in
# the build fixes that; the caches have to go and the daemons that hold them
# have to restart. LaunchServices also kept registrations of the same id at
# paths that no longer exist, so those are dropped and the installed app is
# registered again.
#
# What it does, all at user level, nothing needs sudo:
#   1. drops LaunchServices registrations of the bundle id at paths that are gone
#   2. registers APP again
#   3. removes this user's icon caches (com.apple.iconservices, iconservicesagent, dock.iconcache)
#   4. restarts iconservicesagent, usernoted, NotificationCenter and the Dock; macOS relaunches them
#   5. posts one banner so the result is on screen
# If the bell is still there after this, the system-wide store needs root:
#   sudo rm -rf /Library/Caches/com.apple.iconservices.store && killall iconservicesagent
set -euo pipefail

self=${0##*/}
app=${1:-$HOME/Applications/Snotify.app}
label=org.lonkar.snotify
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

die() { printf '%s: error: %s\n' "$self" "$1" >&2; exit 1; }
[[ $(uname -s) == Darwin ]] || die "macOS only"
[[ -d $app ]] || die "no app at $app; run just install first"

# 1. every registered path with this id; the ones that are gone are unregistered
while IFS= read -r path; do
  [[ -n $path ]] || continue
  if [[ ! -d $path ]]; then
    "$lsregister" -u "$path" >/dev/null 2>&1 || true
    printf 'dropped a dead registration: %s\n' "$path"
  fi
done < <("$lsregister" -dump 2>/dev/null | awk -v id="$label" '
  /^path:/ { path=$0; sub(/^path:[ \t]*/, "", path); sub(/ \(0x[0-9a-f]+\)$/, "", path) }
  /^[ \t]*identifier:[ \t]*/ && $2 == id && path ~ /\.app$/ { print path }')
# 2.
"$lsregister" -f "$app" >/dev/null 2>&1 || true
printf 'registered %s\n' "$app"

# 3. the user-level caches
cache=$(getconf DARWIN_USER_CACHE_DIR)
for d in com.apple.iconservices com.apple.iconservicesagent com.apple.dock.iconcache; do
  [[ -e $cache/$d ]] && rm -rf "${cache:?}/$d" && printf 'removed %s%s\n' "$cache" "$d"
done

# 4. the daemons that hold the old icon; each comes back on its own
for p in iconservicesagent usernoted NotificationCenter Dock; do
  killall "$p" 2>/dev/null && printf 'restarted %s\n' "$p" || true
done
sleep 2

# 5.
snotify=$app/Contents/Resources/bin/snotify
[[ -x $snotify ]] || snotify=$(command -v snotify) || die "snotify is not on PATH"
"$snotify" --title "Snotify icon check" --body "This banner should carry the green slime icon." --sound Pop --group snotify-icon
printf 'posted a banner; if it still shows the old icon, run the sudo line in the header of %s\n' "$0"
