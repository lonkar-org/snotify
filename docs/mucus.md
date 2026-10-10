# Mucus: what Snotify is and won't be

The things underneath that don't change. Features come and go, this stays.

## It takes what you give it

Snotify is a place notifications land. Anything that can run a command can
post one: a shell script, a cron job, a CI step, an agent in a tmux pane, an
editor, another app. The integration point is as low as the CLI and if a
socket, a pipe or an HTTP endpoint is ever added it's the same thing with a
different door. There is no gate.

So Snotify doesn't filter, doesn't throttle, doesn't dedupe and doesn't
decide what's important. If something pushes too much you configured it
that way and the fix is in the thing that pushes. The one switch a user
gets is on or off for a sender. Nothing else.

## Never polling

Snotify never asks anyone whether something happened. Posts are pushed to
it and that's the only way in. Nothing in it wakes up on a timer to go and
look.

## Never duplicating

Your notifications, or a type of them from some source, will either land in
the macOS or Linux notification system or in whatever integration is
available in future like Slack or Teams or some other platform and we don't
care which, but Snotify will not duplicate them and they're always stuck in
the history, so either you see them in the notification center or in the
integration of your choice and they're in a file either way.

Integrations are not Snotify's job to build ahead of need. They come on
request or as a contribution and each one is a destination, never a source.

## The sender is responsible

What a notification means, how often it comes, what glyph and colour it
wears and what a click does are all the sender's. Snotify carries them and
records them. A loop that posts every failure is loud because the person
who wrote the loop wanted it loud.

## One history, in files

Every post is one Markdown file a person can read, grep, move or delete.
No database, no account, no sync service in the way. Anything built on the
history, a window, a journal, a view across machines, reads those files.

## Linux is the same thing

The design is the design. A Linux build lives in the same repository in its
own directory with its own code and follows this file.
