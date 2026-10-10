# Snotify

Notifications that stick.

[![CI](https://github.com/lonkar-org/snotify/actions/workflows/ci.yml/badge.svg)](https://github.com/lonkar-org/snotify/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/lonkar-org/snotify?logo=github&logoColor=white&color=success)](https://github.com/lonkar-org/snotify/releases/latest)
[![Homebrew](https://img.shields.io/badge/brew-lonkar--org%2Ftap-fbb040?logo=homebrew&logoColor=white)](https://github.com/lonkar-org/homebrew-tap)
[![Claude Code plugin](https://img.shields.io/badge/Claude%20Code-plugin-d97757)](#claude-code)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-lightgrey?logo=apple)](#install)

<!-- @Yogesh(hint): this paragraph is Claude's draft from the script headers; rewrite it in your words or keep it -->
A desktop notification from a script, under its own name and icon, with a shell command that runs when the banner is clicked and an Info button that opens a window of Markdown the script supplied. Every post goes into a history that a window and a command search. `snotify` is the command every script uses and Snotify.app is the small macOS app behind it. `snotify-claude` is a Claude Code hook that uses both: type `/notify` while Claude is working and a banner comes when the turn ends, the click jumps to the tmux pane Claude ran in and Info shows the last thing it said.

Why an app and not `osascript -e 'display notification'`: that banner is attributed to Script Editor so it carries a Show button that opens an empty Script Editor window and nothing else can be hung on a click, and that's the whole reason this app exists. A bundle of its own posts through `UNUserNotificationCenter`, gets its own row in System Settings > Notifications and is relaunched by macOS when a banner is clicked, which is where `--on-click` runs.

<!-- @Yogesh(gap): a screenshot of a banner and of the Info window; `just snapshot notes.md out.png` renders the window to a PNG without screen capture, the banner needs a real capture -->

## Install

macOS 13 or later. The app is signed ad hoc and not notarized since there's no Developer ID behind this project, so macOS blocks the first launch of a downloaded copy until the quarantine flag is cleared. Each path below says how. The first banner makes macOS ask once whether Snotify may notify; the answer is kept under System Settings > Notifications > Snotify.

### Homebrew

```sh
brew tap lonkar-org/tap
brew trust lonkar-org/tap       # Homebrew 7 won't load a cask from an untrusted tap
brew install --cask --no-quarantine snotify
```

That installs Snotify.app into `/Applications`, puts `snotify` and `snotify-claude` on PATH and pulls in `jq` for the hook. Without `--no-quarantine`, clear the flag by hand as the DMG section says.

### DMG

Download `Snotify-X.Y.Z.dmg` from the [latest release](https://github.com/lonkar-org/snotify/releases/latest), drag Snotify.app to Applications, then:

```sh
xattr -dr com.apple.quarantine /Applications/Snotify.app
mkdir -p ~/.local/bin
ln -s /Applications/Snotify.app/Contents/Resources/bin/snotify ~/.local/bin/snotify
ln -s /Applications/Snotify.app/Contents/Resources/bin/snotify-claude ~/.local/bin/snotify-claude
```

The command, the hook and the skill travel inside the bundle under `Contents/Resources` so the DMG is a complete install. `checksums.txt` beside it on the release carries the sha256.

### From source

Needs `swiftc` from the Xcode command line tools and [just](https://github.com/casey/just).

```sh
git clone https://github.com/lonkar-org/snotify
cd snotify
just install            # builds, signs, installs ~/Applications/Snotify.app, links ~/.local/bin/snotify and snotify-claude and ~/.claude/skills/notify
just test               # posts a banner; click it and the test says whether the click ran
just test --scheduled   # the same, posted by a one-off LaunchAgent, the way a scheduled job's banner arrives
```

A local build isn't quarantined so there's nothing to clear. The signature is ad hoc with a fixed identifier and the notification permission is remembered by it, so a rebuild doesn't ask again.

## Use

```text
snotify --title TITLE [--body BODY] [--subtitle TEXT] [--sound NAME|default]
       [--group KEY] [--on-click 'shell command']
       [--info-file PATH.md | --info-md 'markdown']
       [--from LABEL] [--icon GLYPH] [--color COLOR] [--meta KEY=VALUE]...
```

| Flag | What it does |
| --- | --- |
| `--sound` | a system sound by name (`Basso`, `Pop`, `Glass`, see `/System/Library/Sounds`) or `default`; silent when absent |
| `--group` | a repeat with the same key replaces the earlier banner |
| `--on-click` | run by `/bin/sh` when the banner is clicked, with the PATH and working directory of the caller; background anything slow |
| `--info-file` | Markdown behind an Info button on the banner (hover for it); the window shows it selectable, links live, with a Copy button. `-` reads stdin |
| `--info-md` | the same, given inline |
| `--from` | who is sending, as the history and the menu bar show it; without it the calling process's name stands in |
| `--icon` | a Nerd Fonts glyph by name (`fa-rocket`, `md-robot`, `snotify icons rocket` searches the 10,996 names), `sf:NAME` for an SF Symbol, `U+F135` for a codepoint or any one character; shown beside the banner's text and in the history |
| `--color` | the icon's colour: `red orange yellow green mint teal cyan blue indigo purple pink brown gray` or `#rrggbb` |
| `--meta` | `KEY=VALUE` kept with the history entry, repeatable; `snotify history key:value` finds it |

Exit 0 posted, 2 usage, 3 notifications are turned off for Snotify.app.

```sh
snotify --title "Backup done" --body "412 files, 2 min" --sound Glass --group backup \
  --from backup.sh --icon fa-rocket --color orange --meta files=412 \
  --on-click 'open ~/Backups' --info-file /tmp/backup.log.md
```

A script that posts the same thing every night gets the same glyph in the same colour every night so the banner is recognisable before it's read and the history is one `snotify history from:backup.sh` away.

The Info window also opens directly and that's how the rendering is checked from a script: `Snotify --show-info notes.md` and, with `--snapshot out.png`, a PNG of it without screen capture or its permission. `just snapshot notes.md out.png` is that.

Without the app `snotify` falls back to `osascript` on macOS and `notify-send` elsewhere, title, body and sound only; a click then doesn't do anything and nothing is kept. `SNOTIFY_APP` points it at a bundle somewhere else.

## History

Posted once, stuck for 90 days.

Every post is one Markdown file under `~/.local/state/snotify/history`, named by the time it was posted. The frontmatter is everything known about it and the body is the Info text so the file is the Info file too and `rg` over the directory is already a search:

```yaml
---
id: "backup"
time: "2026-10-10T20:03:42+05:30"
title: "Backup done"
body: "412 files, 2 min"
sound: "Glass"
group: "backup"
on_click: "open ~/Backups"
from: "backup.sh"
icon: "fa-rocket"
color: "orange"
meta:
  files: "412"
sender:
  process: "backup.sh"
  pid: "51191"
  command: "bash /Users/you/bin/backup.sh"
  ancestry: "backup.sh(51191) < zsh(51189) < tmux(93018) < launchd(1)"
  cwd: "/Users/you"
  tty: "/dev/ttys003"
  user: "you"
  host: "laptop.local"
terminal:
  program: "tmux"
  app: "com.mitchellh.ghostty"
  tmux_pane: "%16"
status: "posted"
outcome:
  clicked: "2026-10-10T20:04:10+05:30"
---

# Backup

All **good**.
```

The sender block is read from the kernel at post time so a script gets attributed without saying who it is; `--from` is the name you'd rather see. A job started by launchd carries its label as `sender.launchd`. What happens afterwards is appended under `outcome`: `clicked`, `info_opened`, `dismissed`, or `replaced_by` when a repeat with the same `--group` took its place.

```sh
snotify history                       # the last 20, newest first
snotify history from:claude --since 7d
snotify history project:myrepo clicked: --json
snotify history deploy --limit 100 --paths | xargs grep -l rollback
snotify config retention 30           # days; `forever` keeps everything, 90 is the default
```

Every word has to match somewhere in the file. A word with a colon, `from:claude` or `process:backup.sh`, matches one field by its key or the last part of its dotted key.

### The window

A search field, the list with each sender's glyph and the selected entry in full with Run Click Command (the same command the banner's click would've run), Reveal in Finder and Copy. It opens from a double-click on Snotify.app, from Spotlight, with Cmd-Y, from the menu bar item, or with `snotify show [QUERY]`, which hands the query to the instance already running when there is one and opens its own otherwise. `snotify show --snapshot out.png` renders it to a file the way `just snapshot` renders the Info window, no screen capture involved.

### Menu bar, Dock, login

Nothing runs between banners unless you ask. Three settings, each off until set:

```sh
snotify config menubar on    # a bell in the menu bar: the last eight, History, the toggles, Quit
snotify config dock on       # a Dock icon while the app runs
snotify config login on      # ~/Library/LaunchAgents/org.lonkar.snotify.plist runs it resident at login
snotify config               # all four, retention included
```

With the menu bar or the Dock icon on, the app stays after its window closes and takes the clicks; with login on it is there from the start. With all three off the window still opens from Finder or `snotify show` and the app quits when you close it.

## Claude Code

Type `/notify` while Claude is working or right before the next prompt and a banner comes when the turn ends. Its click switches tmux to the pane Claude ran in and brings your terminal forward and its Info button holds the whole last message as Markdown. If Claude stops for a permission or a question while the session is armed a "Claude asks" banner comes first and the session stays armed for the finish. Needs `jq` and Snotify.app installed as above.

### As a plugin

In Claude Code:

```text
/plugin install snotify --marketplace lonkar-org/snotify
```

or `/plugin marketplace add lonkar-org/snotify` and then `/plugin install snotify@snotify`. The plugin carries the hooks and the skill so nothing in `settings.json` changes and there isn't a path to get wrong. Inside a plugin the skill is spelled `/snotify:notify`; `notify me` typed as plain words does the same and is shorter, and the hook accepts every spelling.

### By hand

The same hooks in `~/.claude/settings.json`, with `snotify-claude` on PATH (Homebrew's link or the one `just install` makes) and the skill linked from the bundle or the clone so `/notify` is the bare spelling:

```json
"UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "snotify-claude prompt" }] }],
"Notification":     [{ "matcher": "permission_prompt|agent_needs_input|elicitation_dialog|elicitation_url_dialog", "hooks": [{ "type": "command", "command": "snotify-claude asked" }] }],
"PreToolUse":       [{ "matcher": "AskUserQuestion", "hooks": [{ "type": "command", "command": "snotify-claude asked" }] }],
"Stop":             [{ "hooks": [{ "type": "command", "command": "snotify-claude stop" }] }]
```

```sh
ln -s /Applications/Snotify.app/Contents/Resources/skills/notify ~/.claude/skills/notify
```

### What to type

| Prompt | Effect |
| --- | --- |
| `/notify`, `notify me` | arm this session; the banner says "Claude finished in `<project>`" and the first line of the last message |
| `/notify tests are green` | arm, with your own words as the body |
| `/notify deploy \| all green on staging` | arm, with your own subject and body |
| `/notify deploy -` | arm, with your own subject and Claude's message as the body |
| `/notify off` | disarm |
| `/notify` typed while Claude is busy | the banner comes when the running work ends or a few seconds after it if the work had just finished and nothing else was queued |
| armed and Claude stops to ask | a "Claude asks" banner for a permission prompt or a question and the session stays armed for the finish |
| `snotify-claude status` | the armed sessions, from a shell |

The skill itself is only the acknowledgement line; the hooks don't need any help from Claude and the skill doesn't run a command. The terminal a click brings forward is the one `TERM_PROGRAM` named when the session was armed (Ghostty, iTerm, Terminal, WezTerm, kitty, VS Code, Alacritty) and `SNOTIFY_CLAUDE_TERMINAL` overrides it with any name `open -a` accepts. Without tmux the click only brings the terminal forward, and without a known terminal it doesn't do anything.

## Layout

- `Sources/main.swift`: the app's entry, the command line and the lifecycle: post and exit, a subcommand, resident, or launched by macOS for a click. `History.swift` is the file format and the sender lookup, `HistoryWindow.swift` the window, `Icons.swift` the glyphs, `Resident.swift` the settings, the login agent and the menu bar item, `Markdown.swift` and `InfoWindow.swift` the Info rendering, which VoiceOver reads.
- `Sources/icon.swift`: draws the app's icon set at build time. `Resources/nerd-fonts/`: Symbols Nerd Font Mono and its name index, vendored by `scripts/fetch-nerd-font.sh` from a pinned release.
- `bin/snotify`: the command. `bin/snotify-claude`: the Claude Code hook. Both print their header comment as usage.
- `skills/notify`: the `/notify` skill. `hooks/hooks.json` and `.claude-plugin/`: the plugin.
- `scripts/snotify-app.sh`: build, dmg, install, status, test, uninstall. `scripts/snotify-app-test.sh`: the built app against a temporary state directory. `scripts/snotify-claude-test.sh`: the hook against fake transcripts. `scripts/snotify-demo.sh`: twenty demo notifications from four mocked senders, `just demo`.
- `homebrew/`: the cask and the script that points it at a release; the release workflow copies them into [lonkar-org/homebrew-tap](https://github.com/lonkar-org/homebrew-tap).
- `.github/workflows/`: `ci.yml` runs what `just ci` runs, `release.yml` builds the DMG on a `v*` tag and publishes after an approval, `markdown.yml` lints the Markdown.

`just` lists every recipe. `just ci` is the pre-push check and [CONTRIBUTING.md](CONTRIBUTING.md) has the rest, how a release is cut included.

## License

MIT, see [LICENSE](LICENSE). Security reports go through [SECURITY.md](SECURITY.md), not an issue.
