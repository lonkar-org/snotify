# Contributing

Patches welcome, including the ones that tell me I got something wrong.

## Before you push

```sh
just ci
```

That runs shellcheck over the scripts, the hook's test suite, markdownlint,
the plugin validator and the review-marker check, and CI runs the same, so a
pull request that's going to fail does it here rather than in review. The
hook suite posts one real banner through whatever `snotify` finds; that's
expected.

`just test-app` builds the app and runs `scripts/snotify-app-test.sh` against
it, which is what CI's macOS job does: the history files a post writes, the
search, the icons, the settings and the window rendered to a PNG. `just
formula-test` installs the Homebrew formula from a tarball of HEAD through a
throwaway tap and removes it again, the way release.yml proves a tag. Both
need `swiftc` from the Xcode command line tools.

## What a change needs

It fits [docs/mucus.md](docs/mucus.md). A change that polls, filters,
throttles or shows a post twice doesn't go in whatever else it does.

- **A step in `scripts/snotify-claude-test.sh`** for anything the hook does
  differently, and one in `scripts/snotify-app-test.sh` for anything the app
  does differently. The first drives `bin/snotify-claude` with fake transcripts
  and hook events, no Claude Code involved; the second drives a built
  Snotify.app with a temporary state directory and a test settings domain, so
  nothing on your machine changes. Every case that has gone wrong once is a
  step in one of them.
- **bash 3.2.** `bin/snotify` and `bin/snotify-claude` run on whatever `bash`
  is on PATH, and on a Mac without Homebrew that is the 3.2 Apple ships: no
  `mapfile`, no associative arrays, no `${var,,}`.
- **The header comment of the script you changed** kept true. `bin/snotify`,
  `bin/snotify-claude` and `scripts/snotify-app.sh` print their own header as
  usage, so the comment is the documentation.
- **A line in `CHANGELOG.md` under `## Unreleased`**, and the README if the
  behaviour a user sees changed.
- **No review marker left in the tree.** A marker is an at-sign, the name
  Yogesh or claude and a subject in parentheses, in the file's own comment
  syntax; it's a question for the owner, and `scripts/check-review-marks.sh`
  fails the release on one.

## Reporting something broken

Say how you installed it (brew or `just install`), your macOS version,
and for the Claude Code hook what `snotify-claude status` prints and the hook
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

## Backlog

Ideas that are parked, not promised. Open an issue if you want one of them.

- A journal view: `snotify journal yesterday`, the day's entries grouped by
  hour and then by sender, session or group, with replaced banners folded
  into their last one. The files already hold what it needs, so it's read
  side only.
- Threads: a `--thread KEY` that stacks banners in Notification Center
  without replacing them and groups them in the history. A parent id per
  post was looked at and dropped since shell scripts won't carry one.
- Linux, then the history across devices.
- The sneeze, the default sound that counts a burst: `docs/sneeze.md` has
  the decided design, the mechanism ships first on cut system sounds and the
  synthesised voice comes after.

## Licence

MIT, the same as the rest of the repository. By sending a patch you're agreeing
it can ship under that licence.
