# Contributing

Patches welcome, including the ones that tell me I got something wrong.

## Before you push

```sh
just ci
```

That runs shellcheck over the scripts, the hook's test suite, markdownlint,
the plugin validator and the review-marker check, and CI runs the same, so a
pull request that's going to fail does it here rather than in review. The
hook suite posts one real banner through whatever `notify` finds; that's
expected.

`just test-app` builds the app and runs `scripts/notify-app-test.sh` against
it, which is what CI's macOS job does: the history files a post writes, the
search, the icons, the settings and the window rendered to a PNG. `just dmg
dist` builds the DMG the way release.yml does. Both need `swiftc` from the
Xcode command line tools.

## What a change needs

- **A step in `scripts/notify-claude-test.sh`** for anything the hook does
  differently, and one in `scripts/notify-app-test.sh` for anything the app
  does differently. The first drives `bin/notify-claude` with fake transcripts
  and hook events, no Claude Code involved; the second drives a built
  Notify.app with a temporary state directory and a test settings domain, so
  nothing on your machine changes. Every case that has gone wrong once is a
  step in one of them.
- **bash 3.2.** `bin/notify` and `bin/notify-claude` run on whatever `bash`
  is on PATH, and on a Mac without Homebrew that is the 3.2 Apple ships: no
  `mapfile`, no associative arrays, no `${var,,}`.
- **The header comment of the script you changed** kept true. `bin/notify`,
  `bin/notify-claude` and `scripts/notify-app.sh` print their own header as
  usage, so the comment is the documentation.
- **A line in `CHANGELOG.md` under `## Unreleased`**, and the README if the
  behaviour a user sees changed.
- **No review marker left in the tree.** A marker is an at-sign, the name
  Yogesh or claude and a subject in parentheses, in the file's own comment
  syntax; it's a question for the owner, and `scripts/check-review-marks.sh`
  fails the release on one.

## Reporting something broken

Say how you installed it (brew, DMG or `just install`), your macOS version,
and for the Claude Code hook what `notify-claude status` prints and the hook
lines from `claude --debug`. If a click did nothing, say which terminal you
run Claude Code in: the click brings the terminal forward by the name
`TERM_PROGRAM` gave when the session was armed.

## Cutting a release

```sh
just release 0.2.0
```

That checks the tree is clean and on main with no review marker, moves the
Unreleased section of `CHANGELOG.md` under a dated heading, sets the version
in `.claude-plugin/plugin.json`, commits, tags `v0.2.0` and pushes. The
release workflow does the rest and waits on the `release` environment for an
approval before publishing. CONTRIBUTING in `.github/workflows/release.yml`'s
header has the deploy key the Homebrew tap needs.

## Licence

MIT, the same as the rest of the repository. By sending a patch you're agreeing
it can ship under that licence.
