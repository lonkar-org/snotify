---
name: notify
argument-hint: '[[subject |] message | subject -]'
description: Arm a desktop notification for the end of the current work. Typed as /notify (or /notification-companion:notify from the plugin, or `notify me` in plain words) while Claude is working, or right before the next prompt, it makes the Stop hook post a banner through Notify.app (notification-companion) when the turn ends. /notify TEXT puts your own words on the banner, /notify SUBJECT | TEXT names it too, /notify SUBJECT - is your subject with Claude's message, /notify off disarms.
---

# notify

The arming is done by the `UserPromptSubmit` hook, from the plugin's
`hooks/hooks.json` or the same entry in `~/.claude/settings.json`, which runs
`notify-claude prompt` and sees `/notify`, arguments included, before Claude
does. Installed as the plugin the skill is `/notification-companion:notify`,
and the hook accepts that spelling and `notify me` in plain words. The `Stop` hook runs `notify-claude stop` and posts the banner for
an armed session; the `Notification` and `AskUserQuestion` hooks post "Claude
asks" when an armed session stops for a decision. Nothing here needs Claude to
remember or run anything, so this skill is the acknowledgement, nothing more.
There is no fallback command: the Bash tool has no session id to arm with, and
a command that cannot work only costs a permission prompt.

When this skill loads:

1. If you were in the middle of work, carry on with it. Say nothing about the
   notification; the banner is the acknowledgement.
2. If you were idle, answer in one line: "Armed, you'll get a banner when the next
   turn ends." The Stop hook knows this turn was the arming one and waits.

The text after `/notify` is the banner's own words: `/notify tests are green`
sets the body, `/notify deploy | all green on staging` sets the subject and the
body, `/notify deploy -` sets the subject and keeps Claude's message as the body.
Without it the banner says "Claude finished in `<project>`" and the first line of
the last message. `/notify off` disarms. `notify-claude status` lists
the armed sessions.
