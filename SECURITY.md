# Security Policy

## Supported Versions

Fixes land on the latest release. I don't backport to older lines, so
upgrading is the fix.

## Reporting a Vulnerability

Please don't open a public issue for it. Report it privately through GitHub
instead:

<https://github.com/lonkar-org/notification-companion/security/advisories/new>

Tell me what you found, your macOS version, how you installed it, and the
steps to reproduce it.

What happens next:

- I'll acknowledge the report within 7 days. This is maintained by one
  person, so it's sometimes faster and occasionally not.
- I'll tell you whether I can reproduce it and whether I consider it a
  vulnerability, and why if I don't.
- If it is one, I'll work on a fix in a private fork, agree a disclosure date
  with you, and publish a release and a GitHub security advisory together.
  You'll be credited in the advisory unless you'd rather not be.

## What's in scope

Things I'd especially like to hear about:

- `--on-click`: the command travels inside the notification and runs through
  `/bin/sh` when the banner is clicked. Anything that lets text from a title,
  a body or an Info file end up in that command, or lets another process
  change what a pending click will run.
- The Info files under `~/.local/state/notify`: another local user reading
  them, or a path in `--info-file` writing or reading outside that directory.
- `notify-claude`: the hook reads Claude Code's transcript and hook events
  with `jq` and builds a shell command from the tmux pane and terminal name
  it recorded. Anything in a transcript or a prompt that changes that command.
- The release pipeline: the DMG, the checksum and the cask.

Out of scope: anything that needs an attacker who is already your user on
your machine, and bugs in macOS's notification centre, tmux or your terminal
themselves. Report those upstream, though I'm glad to hear about them if
Notify makes them worse.
