# Changelog

Kept in the shape [keep a changelog](https://keepachangelog.com) suggests. One
version covers the app, the `notify` command, the Claude Code plugin and the
Homebrew cask; `just release X.Y.Z` cuts the next section from Unreleased.

## Unreleased

### Added

- Notify.app, a macOS app that posts a notification from the command line
  under its own name and icon, runs a shell command when the banner is clicked
  and shows Markdown behind an Info button. `--group` replaces an earlier
  banner, `--sound` names a system sound, `--on-click` runs through `/bin/sh`
  with the caller's PATH and directory, `--info-file` and `--info-md` feed the
  window, and `--show-info` with `--snapshot` renders it to a PNG without
  screen capture.
- `notify`, the command in front of the app. Without the app it falls back to
  `osascript` on macOS and `notify-send` elsewhere, title, body and sound only.
- `notify-claude`, a Claude Code hook: `/notify` or `notify me` arms the
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
- Claude Code plugin manifests, so `/plugin install notification-companion
  --marketplace lonkar-org/notification-companion` installs the hooks and the
  skill in one step. Inside the plugin the skill is
  `/notification-companion:notify`, and the hook accepts that spelling.
- The terminal a click brings forward is read from `TERM_PROGRAM` when the
  session is armed (Ghostty, iTerm, Terminal, WezTerm, kitty, VS Code,
  Alacritty), with `NOTIFY_CLAUDE_TERMINAL` as the override.
- `scripts/notify-app.sh build` and `dmg`: the app built with `bin/` and
  `skills/` inside it under `Contents/Resources`, and a DMG with an
  Applications link and a `checksums.txt`. `notify` finds the app inside its
  own bundle, in `~/Applications` or in `/Applications`.
- GitHub: CI with shellcheck, the hook tests on Ubuntu and macOS, the plugin
  validator and a signed build; a release workflow that gates the tag, builds
  the DMG, waits on the `release` environment, publishes and pushes the cask
  to `lonkar-org/homebrew-tap`; markdownlint; Dependabot on the actions.
- A Homebrew cask, `brew install --cask lonkar-org/tap/notify`, which puts
  `notify` and `notify-claude` on PATH and depends on `jq`.
