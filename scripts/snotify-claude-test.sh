#!/usr/bin/env bash
# shellcheck disable=SC2016  # backticks in grep patterns are Markdown, not expansions
# snotify-claude-test.sh - exercise bin/snotify-claude with fake transcripts and hook
# events, no Claude Code involved. One real banner is posted by step 4.
#
# Usage: scripts/snotify-claude-test.sh   (or: just test-claude)
#
# Exit 1 on the first step that does not hold. The state goes to a temporary
# XDG_STATE_HOME, so the real armed-session flags are untouched.
set -euo pipefail

here=$(cd -- "$(dirname -- "$0")" && pwd)
nc=$here/../bin/snotify-claude
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
export XDG_STATE_HOME=$t/state
export SNOTIFY_CLAUDE_GRACE=1 # the queued /notify grace period, short for the test
sid=test-session-1
flag=$XDG_STATE_HOME/snotify/claude/$sid

fail() { printf 'FAIL %s\n' "$1" >&2; exit 1; }

# a work turn: the prompt, a tool call, /notify arriving as an attachment, the reply
work=$t/work.jsonl
{
  printf '%s\n' '{"type":"user","message":{"role":"user","content":"fix the build please"}}'
  printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash"}]}}'
  printf '%s\n' '{"type":"user","message":{"content":[{"type":"tool_result","content":"ok"}]}}'
  printf '%s\n' '{"type":"attachment","attachment":{"type":"queued_command","prompt":"/notify"}}'
  printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"**Build fixed.** Two tests were stale.\n\n- a\n- b"}]}}'
} > "$work"
# an idle arming turn: /notify as a user message of its own, and a one-line reply
idle=$t/idle.jsonl
{
  printf '%s\n' '{"type":"user","message":{"role":"user","content":"<command-name>/notify</command-name>\n<command-message>snotify</command-message>"}}'
  printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"Armed."}]}}'
} > "$idle"

pid=p-work # the prompt_id of the turn being worked on; p-arm is the /notify prompt's
event() { # event TRANSCRIPT [PROMPT] [LAST_ASSISTANT_MESSAGE] [PROMPT_ID]
  jq -c -n --arg s "$sid" --arg t "$1" --arg c "$t/myproject" --arg p "${2:-}" --arg m "${3:-}" --arg i "${4:-$pid}" \
    '{session_id: $s, transcript_path: $t, cwd: $c, prompt: $p, prompt_id: $i}
     + (if $m == "" then {} else {last_assistant_message: $m} end)'
}

# A Stop records when the turn ended, and a /notify within two seconds of it
# counts as queued behind finished work. Between steps, pretend a minute passed.
settle() { printf '%s' $(( $(date +%s) - 60 )) > "$XDG_STATE_HOME/snotify/claude/$sid.stop"; }
work_prompt() { event "$work" "fix the build please" "" p-work | "$nc" prompt; }

work_prompt
[[ ! -f $flag ]] || fail "a plain prompt armed the session"
[[ $(cat "$XDG_STATE_HOME/snotify/claude/$sid.last") == p-work ]] || fail "the prompt id was not recorded"
echo "1 ok: a plain prompt leaves it unarmed, and leaves its id"

event "$work" "/notify" "" p-arm | TMUX_PANE=%42 TERM_PROGRAM=ghostty "$nc" prompt
[[ -f $flag ]] || fail "/notify did not arm"
grep -q '^pane=%42$' "$flag" || fail "the pane was not recorded"
grep -q '^terminal=Ghostty$' "$flag" || fail "the terminal was not read from TERM_PROGRAM"
grep -q '^prompt_id=p-arm$' "$flag" || fail "the prompt id was not recorded"
echo "2 ok: /notify armed, pane, terminal and prompt id recorded"

# installed as the plugin, the skill is /snotify:notify
"$nc" disarm "$sid" >/dev/null
event "$work" "/snotify:notify lunch | pizza" "" p-arm | TERM_PROGRAM=iTerm.app SNOTIFY_CLAUDE_TERMINAL=WezTerm "$nc" prompt
[[ -f $flag ]] || fail "the plugin's /snotify:notify did not arm"
grep -q '^title=lunch$' "$flag" || fail "plugin form: subject"
grep -q '^body=pizza$' "$flag" || fail "plugin form: body"
grep -q '^terminal=WezTerm$' "$flag" || fail "SNOTIFY_CLAUDE_TERMINAL did not win over TERM_PROGRAM"
event "$work" "/snotify:notify off" "" p-off | "$nc" prompt
[[ ! -f $flag ]] || fail "the plugin's /snotify:notify off did not disarm"
event "$work" "/notify" "" p-arm | TMUX_PANE=%42 TERM_PROGRAM=ghostty "$nc" prompt
echo "2b ok: the plugin's spelling arms and disarms too"

# inside tmux TERM_PROGRAM says tmux, and the launching app's bundle id is what
# names the terminal; the click then uses `open -b`
"$nc" disarm "$sid" >/dev/null
event "$work" "/notify" "" p-arm | TMUX_PANE=%42 TERM_PROGRAM=tmux __CFBundleIdentifier=com.mitchellh.ghostty "$nc" prompt
grep -q '^terminal=com.mitchellh.ghostty$' "$flag" || fail "the bundle id was not recorded under tmux"
"$nc" disarm "$sid" >/dev/null
event "$work" "/notify" "" p-arm | TMUX_PANE=%42 TERM_PROGRAM=ghostty "$nc" prompt
echo "2c ok: under tmux the terminal comes from __CFBundleIdentifier"

# no prompt since the /notify: the Stop is the arming turn's, stay armed
event "$idle" "" "" p-arm | "$nc" stop
[[ -f $flag ]] || fail "the idle arming turn disarmed"
echo "3 ok: the idle arming turn keeps it armed, no banner"

# armed by hand there is no id, and the transcript decides; an interactive session
# appends the skill body and a system reminder after the /notify prompt
"$nc" disarm "$sid" >/dev/null
interactive=$t/interactive.jsonl
{
  cat "$idle"
  printf '%s\n' '{"type":"user","message":{"content":[{"type":"text","text":"Base directory for this skill: /x/snotify\n\n# snotify"}]}}'
  printf '%s\n' '{"type":"user","message":{"content":"<system-reminder>\nDirectory-scoped variants exist\n</system-reminder>"}}'
  printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"Armed."}]}}'
} > "$interactive"
"$nc" arm "$sid" >/dev/null
event "$interactive" | "$nc" stop
[[ -f $flag ]] || fail "the interactive arming turn, armed by hand, disarmed"
echo "3b ok: armed by hand, the transcript still spots the arming turn behind the skill text"
plugin_idle=$t/plugin-idle.jsonl
{
  printf '%s\n' '{"type":"user","message":{"role":"user","content":"<command-name>/snotify:notify</command-name>\n<command-message>snotify</command-message>"}}'
  printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"Armed."}]}}'
} > "$plugin_idle"
"$nc" arm "$sid" >/dev/null
event "$plugin_idle" | "$nc" stop
[[ -f $flag ]] || fail "the plugin's idle arming turn, armed by hand, disarmed"
echo "3c ok: the plugin's spelling of the arming turn is spotted in the transcript too"
"$nc" disarm "$sid" >/dev/null
settle

# a prompt after the /notify, then that turn's Stop: the banner
event "$work" "/notify" "" p-arm | TMUX_PANE=%42 "$nc" prompt
work_prompt
event "$work" | "$nc" stop
[[ ! -f $flag ]] || fail "the work turn did not disarm"
grep -q '^# Claude finished in myproject$' "$flag.md" || fail "info file title"
grep -q 'Two tests were stale' "$flag.md" || fail "info file reply from the transcript"
grep -q 'tmux pane: `%42`' "$flag.md" || fail "info file pane"
echo "4 ok: the work turn posted a banner (look up) and disarmed"
settle

# the event's own last_assistant_message wins over the transcript, which can lag
event "$work" "/notify" "" p-arm | "$nc" prompt
work_prompt
event "$work" "" "**From the event.** The transcript is behind." | "$nc" stop
[[ ! -f $flag ]] || fail "the second work turn did not disarm"
grep -q 'The transcript is behind' "$flag.md" || fail "info file did not use the event's message"
grep -q 'Two tests were stale' "$flag.md" && fail "info file fell back to the transcript"
echo "4b ok: the event's last message is used when present"
settle

# /notify queued while Claude was busy, with another prompt queued behind it: the
# second prompt is injected into the running turn, whose Stop still carries the
# /notify prompt's id. A prompt came after the /notify, so it posts.
event "$work" "/notify" "" p-arm | "$nc" prompt
event "$work" "done?" "" p-done | "$nc" prompt
event "$work" "" "" p-arm | "$nc" stop
[[ ! -f $flag ]] || fail "a Stop carrying the /notify id did not post although a prompt followed"
echo "4c ok: a prompt injected after a queued /notify posts at that turn's end"

# /notify queued alone: it runs as its own turn right after the work's Stop. Its
# Stop sees no prompt since, so it posts after the grace period, with the work's
# reply rather than the acknowledgement that followed it.
queued=$t/queued.jsonl
{
  printf '%s\n' '{"type":"user","timestamp":"2026-10-10T10:00:00Z","message":{"role":"user","content":"fix the build please"}}'
  printf '%s\n' '{"type":"assistant","timestamp":"2026-10-10T10:00:05Z","message":{"content":[{"type":"text","text":"Build fixed, two tests were stale."}]}}'
  printf '%s\n' '{"type":"user","timestamp":"2026-10-10T10:00:06Z","message":{"role":"user","content":"<command-name>/notify</command-name>\n<command-args>queued | work was done</command-args>"}}'
  printf '%s\n' '{"type":"assistant","timestamp":"2026-10-10T10:00:07Z","message":{"content":[{"type":"text","text":"Armed, you will get a banner."}]}}'
} > "$queued"
event "$work" | "$nc" stop
event "$queued" "/notify queued | work was done" "" p-arm | "$nc" prompt
grep -q '^queued=1$' "$flag" || fail "a /notify right after a Stop was not marked queued"
event "$queued" "" "Armed, you will get a banner." p-arm | "$nc" stop
[[ -f $flag ]] || fail "the queued /notify turn posted before the grace period"
sleep $((SNOTIFY_CLAUDE_GRACE + 1))
[[ ! -f $flag ]] || fail "the grace period did not post"
grep -q '^# queued$' "$flag.md" || fail "queued banner title"
grep -q 'Build fixed, two tests were stale' "$flag.md" || fail "queued banner should carry the work's reply"
grep -q 'Armed, you will get' "$flag.md" && fail "queued banner carried the acknowledgement"
echo "4d ok: a /notify queued alone posts after the grace period, with the work's reply"
settle

# /notify queued with another prompt behind it, each a turn of its own: the grace
# period sees the next prompt start and backs off, and that prompt's Stop posts
event "$work" | "$nc" stop
event "$queued" "/notify" "" p-arm | "$nc" prompt
event "$queued" "" "Armed." p-arm | "$nc" stop
event "$work" "and now the tests" "" p-work2 | "$nc" prompt
sleep $((SNOTIFY_CLAUDE_GRACE + 1))
[[ -f $flag ]] || fail "the grace period posted although a prompt followed"
event "$work" "" "Tests pass." p-work2 | "$nc" stop
[[ ! -f $flag ]] || fail "the following prompt's Stop did not post"
grep -q 'Tests pass' "$flag.md" || fail "banner should carry the last reply"
echo "4e ok: a queued /notify with a prompt behind it posts after that prompt"
settle

event "$work" | "$nc" stop
echo "5 ok: an unarmed stop is a no-op"
settle

event "$work" "/notify" "" p-arm | "$nc" prompt
event "$work" "/notify off" "" p-off | "$nc" prompt
[[ ! -f $flag ]] || fail "/notify off did not disarm"
echo "6 ok: /notify off disarms"

# custom words: body alone, then subject | body, then the expanded skill form
event "$work" "/notify tests are green" "" p-arm | "$nc" prompt
grep -q '^title=$' "$flag" || fail "a body alone set a title"
grep -q '^body=tests are green$' "$flag" || fail "the body was not recorded"
work_prompt
event "$work" | "$nc" stop
grep -q '^# Claude finished in myproject$' "$flag.md" || fail "custom body kept the default title"
sed -n 3p "$flag.md" | grep -q '^tests are green$' || fail "custom body not in the info file"
echo "8 ok: /notify TEXT sets the body"
settle

event "$work" "/notify deploy | all green on staging " "" p-arm | "$nc" prompt
grep -q '^title=deploy$' "$flag" || fail "subject not recorded, or not trimmed"
grep -q '^body=all green on staging$' "$flag" || fail "body after the pipe not recorded, or not trimmed"
work_prompt
event "$work" | "$nc" stop
grep -q '^# deploy$' "$flag.md" || fail "custom subject is not the info title"
echo "9 ok: /notify SUBJECT | TEXT sets both"
settle

# subject with a dash: your subject, Claude's message
event "$work" "/notify deploy -" "" p-arm | "$nc" prompt
grep -q '^title=deploy$' "$flag" || fail "subject before a dash not recorded"
grep -q '^body=$' "$flag" || fail "a dash left a body"
work_prompt
event "$work" "" "**Shipped.** Nothing failed." | "$nc" stop
grep -q '^# deploy$' "$flag.md" || fail "dash form: title"
sed -n 3p "$flag.md" | grep -q 'Shipped' || fail "dash form: body should be the reply"
event "$work" "/notify deploy | -" "" p-arm | "$nc" prompt
grep -q '^title=deploy$' "$flag" || fail "subject | - : title"
grep -q '^body=$' "$flag" || fail "subject | - : body should be empty"
"$nc" disarm "$sid" >/dev/null
settle
echo "9b ok: /notify SUBJECT - and SUBJECT | - keep Claude's message as the body"

event "$work" $'<command-name>/notify</command-name>\n<command-message>snotify</command-message>\n<command-args>lunch | pizza is here</command-args>' "" p-arm | "$nc" prompt
grep -q '^title=lunch$' "$flag" || fail "expanded form: subject"
grep -q '^body=pizza is here$' "$flag" || fail "expanded form: body"
"$nc" disarm "$sid" >/dev/null
echo "10 ok: the expanded skill form carries the text in command-args"

# asked: a permission prompt or a question while armed posts and stays armed; the
# same event while unarmed is nothing
event "$work" | SNOTIFY_CLAUDE_GRACE=0 "$nc" stop
settle
jq -c -n --arg s "$sid" '{session_id: $s, hook_event_name: "Notification", message: "Claude needs your permission to run rm"}' | "$nc" asked
[[ ! -f $flag.asked.md ]] || fail "asked posted while unarmed"
event "$work" "/notify" "" p-arm | "$nc" prompt
jq -c -n --arg s "$sid" --arg c "$t/myproject" '{session_id: $s, cwd: $c, hook_event_name: "Notification", message: "Claude needs your permission to run rm"}' | "$nc" asked
[[ -f $flag ]] || fail "asked disarmed the session"
grep -q '^# Claude asks in myproject$' "$flag.asked.md" || fail "asked title"
grep -q 'permission to run rm' "$flag.asked.md" || fail "asked message"
jq -c -n --arg s "$sid" --arg c "$t/myproject" '{session_id: $s, cwd: $c, hook_event_name: "PreToolUse", tool_name: "AskUserQuestion", tool_input: {questions: [{question: "Squash or rebase?"}]}}' | "$nc" asked
grep -q 'Squash or rebase?' "$flag.asked.md" || fail "asked took the AskUserQuestion text"
"$nc" disarm "$sid" >/dev/null
echo "11 ok: a question or permission prompt posts while armed and keeps it armed"

"$nc" arm by-hand-1 >/dev/null
"$nc" status | grep -q '^by-hand-1 ' || fail "status does not list the armed session"
"$nc" disarm by-hand-1 >/dev/null
echo "7 ok: arm, status, disarm by hand"
