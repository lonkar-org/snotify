#!/usr/bin/env bash
# snotify-demo.sh - fill the history with a demo set: twenty notifications from
# four mocked senders (backup.sh, deploy.sh, watchdog.sh and Claude Code), each
# with its own glyph and colour, some with Info Markdown, a click command, a
# group that replaces an earlier banner, and extra --meta keys. The point is a
# history window with something in it: open it with `snotify show` after.
#
# Usage: scripts/snotify-demo.sh [--quiet]      (or: just demo)
#   --quiet   post with no sound (the default has none either, this also drops
#             the per-entry echo)
#
# Each sender is a small script in a temp dir that runs `snotify "$@"`, so the
# entry's sender.process is the mock's name and not this script. Twenty banners
# will stack in Notification Center; clear them there or let them scroll.
set -euo pipefail

quiet=0
[[ ${1:-} == --quiet ]] && quiet=1

command -v snotify >/dev/null || { echo "snotify is not on PATH; run just install first" >&2; exit 1; }

t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT

# mock NAME: a script that forwards to notify, so the kernel-side sender is NAME
mock() {
  printf '#!/usr/bin/env bash\nsnotify "$@"\n' > "$t/$1"
  chmod +x "$t/$1"
}
mock backup.sh
mock deploy.sh
mock watchdog.sh
mock claude-code

n=0
# send MOCK ARGS...
send() {
  local who=$1; shift
  n=$((n + 1))
  [[ $quiet -eq 1 ]] || { printf "%2d  %-12s %s\n" "$n" "$who" "$*" | tr "\n" " " | cut -c1-110; echo; }
  "$t/$who" "$@" || echo "   (post $n exited $?)" >&2
}

# backup.sh: nightly rsync, a glyph per outcome, one group so the window shows replaced_by
send backup.sh --title "Backup started" --body "home → nas, 41,206 files" --from backup.sh \
  --icon md-harddisk --color blue --group backup --meta host=nas --meta target=/volume1/home
send backup.sh --title "Backup done" --body "412 files changed, 1.3 GB, 4 m 12 s" --from backup.sh \
  --icon fa-check_circle --color green --group backup --meta host=nas --meta files=412 \
  --info-md $'# Backup 2026-10-10\n\n| | |\n|---|---|\n| changed | 412 |\n| size | 1.3 GB |\n| time | 4 m 12 s |\n\nNothing was deleted.' \
  --on-click "open /Volumes/home"
send backup.sh --title "Backup skipped" --body "nas is not reachable, retry in 1 h" --from backup.sh \
  --icon md-lan_disconnect --color orange --meta host=nas
send backup.sh --title "Backup failed" --body "rsync exited 23, partial transfer" --from backup.sh \
  --icon fa-warning --color red --meta host=nas --meta exit=23 \
  --info-md $'# rsync exit 23\n\n```\nrsync: send_files failed to open "/Users/yogesh/Library/Caches/x": Permission denied (13)\n```\n\nA cache file, safe to ignore, add it to the excludes.'
send backup.sh --title "Old snapshots pruned" --body "kept 30 daily, 12 weekly, removed 9" --from backup.sh \
  --icon md-broom --color gray --meta removed=9

# deploy.sh: CI for an imaginary service, with git meta
send deploy.sh --title "Deploy staging" --subtitle "api v2.14.0" --body "rolling out 3 pods" --from deploy.sh \
  --icon fa-rocket --color teal --group deploy-staging --meta env=staging --meta sha=9f3c1a2 --meta service=api
send deploy.sh --title "Deploy staging done" --subtitle "api v2.14.0" --body "3/3 healthy in 48 s" --from deploy.sh \
  --icon fa-check_circle --color green --group deploy-staging --meta env=staging --meta sha=9f3c1a2 \
  --on-click "open https://staging.example.invalid/health"
send deploy.sh --title "Tests failed" --subtitle "api PR #318" --body "2 of 1,204 failed" --from deploy.sh \
  --icon md-test_tube --color red --meta pr=318 --meta sha=b17e0dd \
  --info-md $'# PR #318, 2 failed\n\n- `test_rate_limit_resets_after_window`\n- `test_rate_limit_headers`\n\nBoth time based, both flaky since the clock change. Rerun passed.'
send deploy.sh --title "Merged" --subtitle "api PR #318" --body "rate limit window fix" --from deploy.sh \
  --icon oct-git_merge --color purple --meta pr=318
send deploy.sh --title "Deploy production" --subtitle "api v2.14.0" --body "waiting for approval" --from deploy.sh \
  --icon fa-clock --color orange --group deploy-prod --meta env=production --meta sha=9f3c1a2 \
  --on-click "open https://ci.example.invalid/approve/4471"
send deploy.sh --title "Deploy production done" --subtitle "api v2.14.0" --body "6/6 healthy, p95 118 ms" --from deploy.sh \
  --icon fa-check_circle --color green --group deploy-prod --meta env=production --meta sha=9f3c1a2
send deploy.sh --title "Image pushed" --body "ghcr.io/example/api:2.14.0, 184 MB" --from deploy.sh \
  --icon md-package --color blue --meta sha=9f3c1a2

# watchdog.sh: host monitoring, a glyph per signal
send watchdog.sh --title "Disk 91% on nas" --body "/volume1 has 38 GB left" --from watchdog.sh \
  --icon md-harddisk --color orange --meta host=nas --meta mount=/volume1 --meta pct=91
send watchdog.sh --title "Load high" --body "1-min load 14.2 on 8 cores, 10 min" --from watchdog.sh \
  --icon oct-cpu --color red --meta host=builder --meta load=14.2 \
  --info-md $'# builder load\n\n```\n PID  %CPU COMMAND\n4412  620  swift-frontend\n4418  180  clang\n```\n\nA full rebuild, it finished on its own.'
send watchdog.sh --title "Certificate expires in 9 days" --body "example.invalid, 2026-10-19" --from watchdog.sh \
  --icon fa-shield --color yellow --meta host=web --meta days=9 \
  --on-click "open https://example.invalid"
send watchdog.sh --title "Service recovered" --body "postgres on db1, down 2 m 40 s" --from watchdog.sh \
  --icon fa-heart_pulse --color green --meta host=db1 --meta service=postgres
send watchdog.sh --title "Memory 96%" --body "db1, swap in use" --from watchdog.sh \
  --icon fa-memory --color red --meta host=db1 --meta pct=96

# Claude Code: the shape the hook sends, a robot, teal on finish and orange on a question
send claude-code --title "Claude Code finished" --subtitle "snotify" --body "History and the window are in, tests green" \
  --from "Claude Code" --icon md-robot --color teal --meta claude_session=demo-1 --meta project=snotify \
  --info-md $'# Claude Code\n\nTwo commits on main, tree clean.\n\n- a7e7cc6 vendor the Nerd Font\n- ee7336a history, glyphs, the window'
send claude-code --title "Claude Code has a question" --subtitle "vachan" --body "Keep the old redirects or drop them?" \
  --from "Claude Code" --icon md-robot --color orange --meta claude_session=demo-2 --meta project=vachan
send claude-code --title "Claude Code is idle" --subtitle "runner-fleet" --body "Waiting on you for 10 minutes" \
  --from "Claude Code" --icon md-robot --color gray --meta claude_session=demo-3 --meta project=runner-fleet

echo "posted $n; open the window with: snotify show"
