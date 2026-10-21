#!/usr/bin/env bash
# snotify-preview.sh - build Snotify.app from Sources/ and render its history
# window to a PNG over a synthesised history, so a change to the window can be
# looked at without posting a banner or touching the real history.
#
# Usage: scripts/snotify-preview.sh OUT.png [--dark] [QUERY...]   (or: just preview out.png)
#   OUT.png   where the render goes
#   --dark    render in dark mode
#   QUERY     a search to start the window with, `from:backup.sh` say
#
# The build goes to a temp dir and the history is 65 entries over the last
# three months from five senders, with click commands, Info text, outcomes
# and a few failures, written as files; nothing is posted. The settings go to
# a throwaway defaults domain.
#
# Found on 2026-10-17: the binary has to run from inside a bundle, since
# UNUserNotificationCenter asserts otherwise, so a plain swiftc build cannot
# be used for the render; the build script's bundle can.
set -euo pipefail

self=${0##*/}
here=$(cd -- "$(dirname -- "$0")" && pwd)
out=${1:?usage: $self OUT.png [--dark] [QUERY...]}
shift
case $out in /*) ;; *) out=$PWD/$out ;; esac

t=$(mktemp -d)
suite=org.lonkar.snotify.preview.$$
cleanup() { rm -rf "$t"; defaults delete "$suite" >/dev/null 2>&1 || true; }
trap cleanup EXIT

"$here/snotify-app.sh" build "$t/app" >/dev/null

hist=$t/state/snotify/history
mkdir -p "$hist"
senders=("backup.sh|md-harddisk|blue" "deploy.sh|fa-rocket|teal" "watchdog.sh|fa-warning|red" "Claude Code|md-robot|purple" "cron||")
titles=("Backup done|412 files changed, 1.3 GB, 4 m 12 s" "Deploy staging done|3/3 healthy in 48 s" "Disk 91% on nas|/volume1 has 38 GB left" "Claude Code finished|History and the window are in, tests green" "Nightly report|all 14 jobs ran")
i=0
for back in 0 0 0 1 1 2 2 2 2 3 5 5 6 7 7 7 8 9 11 12 12 14 15 15 16 18 19 20 21 21 21 24 25 27 29 30 31 33 35 36 38 40 40 41 45 46 48 50 52 55 58 60 61 63 65 66 70 72 75 77 80 82 84 85 88; do
  i=$((i + 1))
  k=$((i % 5))
  IFS='|' read -r from icon color <<< "${senders[$k]}"
  IFS='|' read -r title body <<< "${titles[$k]}"
  hour=$((8 + i % 12)); min=$(( (i * 7) % 60 ))
  day=$(date -v-"${back}"d +%Y-%m-%d)
  stamp=$(printf '%sT%02d-%02d-00.000' "$day" "$hour" "$min")
  iso=$(printf '%sT%02d:%02d:00%s' "$day" "$hour" "$min" "$(date +%z | sed 's/\(..\)$/:\1/')")
  f=$hist/$stamp-$(printf '%06x' $((i * 4099)) ).md
  {
    echo '---'
    echo "id: \"demo-$i\""
    echo "time: \"$iso\""
    echo "title: \"$title\""
    [[ $k -eq 1 ]] && echo 'subtitle: "api v2.14.0"'
    echo "body: \"$body\""
    [[ $((i % 3)) -eq 0 ]] && echo 'sound: "Glass"'
    echo "from: \"$from\""
    [[ -n $icon ]] && { echo "icon: \"$icon\""; echo "color: \"$color\""; }
    [[ $((i % 2)) -eq 0 ]] && echo 'on_click: "open ~/Backups"'
    echo 'meta:'; echo '  host: "nas"'; echo "  run: \"$i\""
    echo 'sender:'; echo "  process: \"$from\""; echo "  pid: \"$((5000 + i))\""
    echo "  command: \"bash /Users/you/bin/$from --nightly\""
    echo "  ancestry: \"$from($((5000 + i))) < zsh(51189) < tmux(93018) < launchd(1)\""
    echo '  cwd: "/Users/you"'; echo '  tty: "/dev/ttys003"'; echo '  user: "you"'; echo '  host: "laptop.local"'
    echo 'terminal:'; echo '  program: "tmux"'; echo '  app: "com.mitchellh.ghostty"'; echo '  tmux_pane: "%16"'
    if [[ $((i % 7)) -eq 0 ]]; then echo 'status: "failed: notifications are off for Snotify.app"'; else echo 'status: "posted"'; fi
    echo 'outcome:'
    [[ $((i % 4)) -eq 0 ]] && echo "  clicked: \"$iso\""
    [[ $((i % 5)) -eq 1 ]] && echo "  info_opened: \"$iso\""
    [[ $((i % 6)) -eq 2 ]] && echo '  replaced_by: "later.md"'
    echo '---'
    if [[ $((i % 2)) -eq 1 ]]; then
      # shellcheck disable=SC2016  # the backticks are Markdown
      printf '\n# %s\n\n| | |\n|---|---|\n| changed | 412 |\n| size | 1.3 GB |\n\nNothing was **deleted**. See [the log](https://example.invalid/log).\n\n```\nrsync -a --delete ~ nas:/volume1/home\n```\n' "$title"
    fi
  } > "$f"
done

cd "$t"
XDG_STATE_HOME=$t/state SNOTIFY_DEFAULTS_SUITE=$suite \
  "$t/app/Snotify.app/Contents/MacOS/Snotify" show --snapshot "$out" "$@"
printf 'rendered %s over %d entries\n' "$out" "$i"
