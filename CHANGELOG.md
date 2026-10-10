# Changelog

Kept in the shape [keep a changelog](https://keepachangelog.com) suggests. One
version covers the app, the `snotify` command, the Claude Code plugin and the
Homebrew formula; `just release X.Y.Z` cuts the next section from Unreleased.

## Unreleased

### Added

- Snotify.app, a macOS app that posts a notification from the command line
  under its own name and icon, runs a shell command when the banner is clicked
  and shows Markdown behind an Info button. `--group` replaces an earlier
  banner, `--sound` names a system sound, `--on-click` runs through `/bin/sh`
  with the caller's PATH and directory, `--info-file` and `--info-md` feed the
  window, and `--show-info` with `--snapshot` renders it to a PNG without
  screen capture.
- `snotify`, the command in front of the app. Without the app it falls back to
  `osascript` on macOS and `notify-send` elsewhere, title, body and sound only.
- `snotify-claude`, a Claude Code hook: `/notify` or `notify me` arms the
  session and the Stop hook posts a banner when the turn ends, with the first
  line of Claude's last message, a click that switches tmux to the pane Claude
  ran in and brings the terminal forward, and the whole message behind Info.
  A permission prompt or a question while armed posts "Claude asks" and keeps
  the session armed. `/notify TEXT`, `/notify SUBJECT | TEXT` and
  `/notify SUBJECT -` put your own words on the banner; `/notify off` disarms.
  A `/notify` typed while Claude is busy is told apart from one typed while
  idle, and a queued one waits a grace period for a prompt queued behind it.
- The `/notify` skill, which is the acknowledgement line and nothing more; the
  hooks do the work.
- Claude Code plugin manifests, so `/plugin install snotify
  --marketplace lonkar-org/snotify` installs the hooks and the
  skill in one step. Inside the plugin the skill is
  `/snotify:notify`, and the hook accepts that spelling.
- The terminal a click brings forward is read from `TERM_PROGRAM` when the
  session is armed (Ghostty, iTerm, Terminal, WezTerm, kitty, VS Code,
  Alacritty), with `SNOTIFY_CLAUDE_TERMINAL` as the override.
- `scripts/snotify-app.sh build` and `tarball`: the app built with `bin/`
  and `skills/` inside it under `Contents/Resources`, and the source tarball
  with a `checksums.txt` that a release publishes. `snotify` finds the app
  inside its own bundle, in `~/Applications` or in `/Applications`.
- GitHub: CI with shellcheck, the hook tests on Ubuntu and macOS, the plugin
  validator and a signed build; a release workflow that gates the tag, packs
  the tarball, proves the formula installs from it, waits on the `release`
  environment, publishes and pushes the formula to `lonkar-org/homebrew-tap`;
  markdownlint; Dependabot on the actions.
- A Homebrew formula, `brew install lonkar-org/tap/snotify`, which builds the
  app from the release tarball on the user's machine, so nothing is
  quarantined and nothing needs notarizing, puts `snotify` and
  `snotify-claude` on PATH and depends on `jq`. `scripts/formula-test.sh`
  installs it through a throwaway tap in CI and locally.
- A history: every post is one Markdown file under
  `~/.local/state/snotify/history`, named by the time, with the metadata as
  YAML frontmatter (title, body, sound, group, click command, who sent it as
  the calling process, its command line, ancestry, directory, tty, user, host
  and launchd label, the terminal and tmux pane, `--from` and `--meta`) and
  the Info Markdown as the body; what happened after is appended (clicked,
  Info opened, dismissed, replaced by a repeat with the same group). Kept 90
  days by default, `snotify config retention DAYS|forever` changes that.
- `snotify history [QUERY] [--since 7d] [--limit N] [--json | --paths]`
  searches it from a shell, every word matching anywhere or `key:text`
  matching one field (`from:claude`, `process:backup.sh`, `project:myrepo`).
- The history window: a search field, the list with each sender's glyph, the
  selected entry in full with Run Click Command, Reveal in Finder and Copy.
  Opened by a double-click on Snotify.app or Spotlight, Cmd-Y, the menu bar
  item, or `snotify show [QUERY]`, which hands the query to the instance
  already running when there is one. `--snapshot OUT.png` renders it to a
  file without a screen capture.
- A sender's glyph and colour: `--icon fa-rocket --color orange` names one of
  the 10,996 Nerd Fonts glyphs (Symbols Nerd Font Mono v3.5.1 travels in the
  bundle, MIT), `--icon sf:checkmark.seal.fill` an SF Symbol, `U+F135` a
  codepoint, or any single character. It is attached to the banner and marks
  the row in the history and the menu bar. `snotify icons QUERY` searches the
  names and `--png OUT.png` renders one.
- `--from LABEL` names the sender as the history and the menu bar show it, and
  `--meta KEY=VALUE` keeps anything else with the entry. The Claude Code hook
  sends `--from "Claude Code"` with a teal robot for a finish and an orange one
  for a question, plus the session id, the project and the pane.
- Optional menu bar item (`snotify config menubar on`): the last eight
  notifications, History, the three toggles, Quit. Optional Dock icon
  (`snotify config dock on`). Optional launch at login (`snotify config login
  on`), which writes `~/Library/LaunchAgents/org.lonkar.snotify.plist` and runs
  the app resident; off removes it. With none of the three on nothing runs
  between banners, and the window still opens from Finder or `snotify show`.
- The click brings forward the app LaunchServices stamped on the environment
  (`__CFBundleIdentifier`, `open -b`) when `TERM_PROGRAM` only says tmux, so
  the jump back works from inside tmux.
- The name: Snotify, `snotify`, `org.lonkar.snotify`. Notifications that
  stick. Everything that carried the old name follows: the app, the command,
  the hook (`snotify-claude`), the formula, the plugin (`/snotify:notify`), the
  state directory (`~/.local/state/snotify`), the defaults domain, the
  LaunchAgent label and the `SNOTIFY_*` variables. The phrases people type,
  `/notify` and `notify me`, stay.
- The icon: a green splat on a dark square, drawn by `Sources/icon.swift`.
- `just demo` (`scripts/snotify-demo.sh`): twenty notifications from four
  mocked senders, so the history window has something to show.
