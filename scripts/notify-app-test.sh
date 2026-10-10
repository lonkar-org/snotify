#!/usr/bin/env bash
# notify-app-test.sh - exercise a built Notify.app: the history files a post
# writes, the history, icons and config subcommands, and the window rendered
# to a PNG. No click is needed and nothing on the machine is touched: the
# state goes to a temporary XDG_STATE_HOME and the settings to a test defaults
# domain (NOTIFY_DEFAULTS_SUITE), which is deleted at the end.
#
# Usage: scripts/notify-app-test.sh [APP]   (default dist/Notify.app; or: just test-app)
#
# Posting needs the notification permission. Where it is denied, a CI runner
# say, the post exits 3 and the entry still records `status: failed: ...`,
# which is what the first step accepts; every later step reads the files.
# Exit 1 on the first step that does not hold.
set -euo pipefail

here=$(cd -- "$(dirname -- "$0")" && pwd)
app=${1:-$here/../dist/Notify.app}
bin=$app/Contents/MacOS/Notify
[[ -x $bin ]] || { echo "no app at $app; run scripts/notify-app.sh build dist first" >&2; exit 1; }

t=$(mktemp -d)
suite=org.lonkar.notify.test.$$
cleanup() { rm -rf "$t"; defaults delete "$suite" >/dev/null 2>&1 || true; }
trap cleanup EXIT
export XDG_STATE_HOME=$t/state NOTIFY_DEFAULTS_SUITE=$suite
hist=$XDG_STATE_HOME/notify/history

fail() { printf 'FAIL %s\n' "$1" >&2; exit 1; }

# post, with a watchdog: a permission dialog that never gets an answer must
# not hang the suite. 0 is posted, 3 is denied, both leave an entry.
post() { # post COMMAND ARGS...
  "$@" & local pid=$!
  for _ in $(seq 1 40); do kill -0 "$pid" 2>/dev/null || break; sleep 0.5; done
  if kill -0 "$pid" 2>/dev/null; then kill "$pid"; fail "the post did not finish in 20 s"; fi
  wait "$pid" && return 0
  local rc=$?
  [[ $rc -eq 3 ]] || fail "the post exited $rc"
  echo "   (notifications are off here; the entry still records that)"
}

# a script in the middle, so the sender is the script and not this shell. It
# runs the app as a child the way a script runs `notify`, which then execs
# the app, so the app's parent is the script.
caller=$t/backup.sh
printf '#!/usr/bin/env bash\n"$@"\n' > "$caller"
chmod +x "$caller"
post "$caller" "$bin" --title "Backup done" --body "412 files" --from backup.sh --icon fa-rocket --color orange \
  --meta files=412 --group backup --on-click 'true' --info-md $'# Backup\n\nAll **good**.'
f=$(printf '%s\n' "$hist"/*.md | head -1)
[[ -n $f ]] || fail "no history file was written"
grep -q '^title: "Backup done"$' "$f" || fail "title"
grep -q '^from: "backup.sh"$' "$f" || fail "from"
grep -q '^icon: "fa-rocket"$' "$f" || fail "icon"
grep -q '^  files: "412"$' "$f" || fail "meta"
grep -q '^  process: "backup.sh"$' "$f" || fail "the sender process should be the calling script, got: $(grep '^  process' "$f")"
grep -q '^  ancestry: "backup.sh(' "$f" || fail "ancestry starts with the script"
grep -q '^  user: "' "$f" || fail "user"
grep -q '^status: "' "$f" || fail "status"
grep -q '^All \*\*good\*\*\.$' "$f" || fail "the info markdown is the body"
echo "1 ok: a post writes one Markdown file with the metadata as frontmatter"

post "$bin" --title "Backup done" --body "second run" --from backup.sh --group backup
second=$(printf '%s\n' "$hist"/*.md | tail -1)
[[ $second != "$f" ]] || fail "a second post with the same group should be a second file"
grep -q "^  replaced_by: \"$(basename "$second")\"$" "$f" || fail "the first entry should record what replaced it"
echo "2 ok: a repeat with the same group is recorded as replacing the earlier one"

post "$bin" --title "Deploy" --subtitle staging --body "all green" --from deploy --icon sf:checkmark.seal.fill --color green
"$bin" history | grep -q 'deploy *Deploy  —  all green' || fail "history lists the deploy"
[[ $("$bin" history from:backup | wc -l | tr -d ' ') == 2 ]] || fail "from:backup should match two"
[[ $("$bin" history process:backup.sh | wc -l | tr -d ' ') == 1 ]] || fail "process:backup.sh should match the one through the script"
[[ $("$bin" history nothing-like-this) == "no match" ]] || fail "a miss says no match"
[[ $("$bin" history --since 1h --limit 1 --paths) == "$(printf '%s\n' "$hist"/*.md | tail -1)" ]] || fail "--paths with --limit 1 is the newest file"
"$bin" history --json --limit 1 | python3 -I -c 'import json,sys; d=json.load(sys.stdin); assert d[0]["title"]=="Deploy" and "sender.process" in d[0], d' || fail "--json"
echo "3 ok: history lists, searches by word and by key, limits and prints json"

"$bin" icons rocket | grep -q 'fa-rocket  U+F135' || fail "icons search"
"$bin" icons --png "$t/rocket.png" fa-rocket --color orange >/dev/null || fail "icons --png"
"$bin" icons --png "$t/seal.png" sf:checkmark.seal.fill --color green >/dev/null || fail "icons --png sf:"
"$bin" icons --png "$t/char.png" ✓ >/dev/null || fail "icons --png with a character"
file "$t/rocket.png" | grep -q 'PNG image data, 256 x 256' || fail "the png is 256 px square"
! "$bin" --title x --icon no-such-glyph-anywhere 2>/dev/null || fail "an unknown glyph should be refused"
! "$bin" --title x --color notacolour 2>/dev/null || fail "an unknown colour should be refused"
echo "4 ok: icons search and render; an unknown glyph or colour is refused before posting"

[[ $("$bin" config retention) == 90 ]] || fail "retention defaults to 90"
"$bin" config retention 30 >/dev/null
[[ $("$bin" config retention) == 30 ]] || fail "retention set"
"$bin" config menubar on >/dev/null
"$bin" config | grep -q '^menubar: on$' || fail "config lists menubar on"
"$bin" config menubar off >/dev/null
! "$bin" config bogus on 2>/dev/null || fail "an unknown setting should be refused"
echo "5 ok: config reads and writes the settings in the test domain"

# retention: a file named for last year is pruned by the next post
old=$hist/2020-01-01T00-00-00-000000.md
cp "$f" "$old"
post "$bin" --title "Prune trigger" --body ""
[[ ! -f $old ]] || fail "an entry older than the retention was not pruned"
echo "6 ok: an entry older than the retention goes on the next post"

"$bin" show --snapshot "$t/window.png" from:backup || fail "show --snapshot"
file "$t/window.png" | grep -q 'PNG image data' || fail "the window snapshot is a png"
echo "7 ok: the history window renders to a PNG"

echo "all ok"
