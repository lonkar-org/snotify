# Congestion: the gate and its first opening

Decided 2026-10-11, not built yet. This is the design, the reasons, the
decisions taken and what is still open.

## What it is

On 2026-10-10 Slack sent between ten and thirty mails in one day about
messages that had gone unread for a quarter of an hour. None of them were
read and all of them were cleared at the end of the day, which is what a
person does with a pile they didn't ask for. Slack had already done the
sensible thing, bundled the mail and only sent it when the person was away,
and it made no difference: bundled noise is still noise, and "clear all" is
the rational answer to it.

A notifier is worth exactly as much as the trust its banners keep. The
moment a person clears them unread the value is gone, whatever the
individual posts were. So Snotify holds an opinion about the pile, and the
opinion is not a lock. It is the first opening of a gate: defaults that make
the quiet path the easy one, a report that names the sender when the pile
grows, and one line to widen or narrow the gate for anyone who wants sixty
banners a minute. The user owns the gate. Snotify owns where it stands on
day one.

This amends [mucus.md](mucus.md), which said there was no gate at all. The
sender is still responsible for what a post means and the sender's switch is
still on or off; what changes is that a sender who posts more than the
default opening lets through is collapsed on screen until the user widens
it, and the user is told.

## What the research says

- **The baseline is already full.** An in-situ study logged an average of
  63.5 notifications a day per person, mostly messengers and mail
  ([Pielot, Church, de Oliveira 2014](https://ic.unicamp.br/~oliveira/doc/MHCI2014_An-in-situ-study-of-mobile-phone-notifications.pdf));
  a follow-up over 278 users found a median of 56
  ([Pielot, Vradi, Park 2018](https://www.interruptions.net/literature/Pielot-MobileHCI18.pdf)).
  Every new sender lands on top of that.
- **Operations solved it once, by refusing.** The SRE book draws the line at
  pages: a page needs a human and an action, people can only take a few a
  day, and everything else is a log or a dashboard
  ([Monitoring Distributed Systems](https://sre.google/sre-book/monitoring-distributed-systems/)).
  A desktop banner is a page.
- **The platforms gave the mute to the receiver.** Android made channels
  mandatory and once a channel exists the developer cannot change its
  importance; the user decides per category
  ([notification channels](https://developer.android.com/training/notify-user/channels.html)).
  Apple added interruption levels, Focus and the scheduled summary that
  batches the passive posts
  ([UNNotificationInterruptionLevel](https://developer.apple.com/tutorials/data/documentation/usernotifications/unnotificationinterruptionlevel.md),
  [WWDC21](https://www.wwdcnotes.com/notes/wwdc21/10091)). The sender
  classifies, the receiver decides, and "important" is not the sender's call.
- **A good default is a schedule, not a toggle.** Basecamp starts everyone on
  8am to 6pm instead of always-on, because nobody changes a 24/7 default
  ([Work Can Wait](https://medium.com/@jasonfried/basecamp-3-work-can-wait-4adfb285c84b)).
  Slack's away-mail is the opposite case, on by default and bundled every 15
  minutes or every hour, with the off switch behind a setting nobody visits
  ([Slack help](https://slack.com/intl/en-gb/help/articles/218876627)).

## Decisions

- **The gate is the user's; its first opening is ours.** Snotify does not
  limit what a sender may call urgent and does not decide what matters. It
  sets how many posts a sender gets on screen per window by default, the
  user sets anything else, including wide open. Decided 2026-10-11.
- **Every post has a sender.** `--from` already names one; without it the
  sender is the calling script's name. Posts without a sender are refused,
  because a budget, a mute and a report all hang off it.
- **Four levels, the sender picks the lowest honest one.**

  | level    | on screen                               | counted by the budget |
  | -------- | --------------------------------------- | --------------------- |
  | `quiet`  | the list only, no banner                | no                    |
  | `banner` | a banner, the default                   | yes                   |
  | `urgent` | a banner, through quiet hours           | yes                   |
  | `digest` | one banner at the next digest time      | no                    |

  Levels say where a post lands, not how it sounds. Sound stays the tally of
  [sneeze.md](sneeze.md), on by default and advanced by every banner, and a
  `quiet` post neither plays nor advances it.
  <!-- @Yogesh(check): the budget counts banner and urgent together, since you said what we care about is how many urgents reach the screen in a window; or should it count urgent alone and leave banner to the sneeze's collapse? -->
- **The budget: 5 an hour and 20 a day, per sender.** Past it, that sender's
  further posts in the window become one banner, "12 more from tailscale-watch
  since 14:00", replaced in place as the count grows, with the Info window
  listing them. Every post is still in the history; the budget is about the
  screen. The numbers are a start and are reviewed after the first weeks.
- **A state withdraws itself.** "Tailscale is on" is a state, and when it
  clears the banner leaves the list rather than gaining a sibling that says
  "off again". `snotify --clear GROUP` removes delivered banners of that
  group. A post that is an event rather than a state, "Claude finished",
  expires from the list after an hour; the sweep runs at the next post, since
  nothing stays alive. A banner the user has not dismissed in an hour was
  not going to be read.
- **Digests are scheduled by the last post, not by a timer.** A `digest`
  post adds itself to the pending digest and reschedules the summary banner
  for the next digest time with the count and list so far, replacing the one
  scheduled before. macOS delivers it on the calendar trigger with nothing of
  Snotify running, so [mucus.md](mucus.md)'s rule that nothing wakes up on a
  timer holds. Default times 09:00, 13:00 and 18:00 local, nothing in quiet
  hours.
  <!-- @Yogesh(decide): those three times, or the two ends of the work day the way Basecamp does it? -->
- **Quiet hours are shared.** The same `22:00-08:00` that tmux-companion
  keeps; a `banner` in quiet hours lands in the list without a banner, an
  `urgent` goes through. Decided here so the two never disagree.
- **Snotify counts its own noise and names the sender.** For every post the
  history records the level, the sender, and what became of it: clicked,
  Info opened, dismissed by hand, swept by "clear all", or expired. macOS
  reports a dismissal when the category asks for it (`customDismissAction`)
  and a "clear all" arrives as a dismissal of each one. From that, per
  sender and per week: posted, reached the screen, clicked, dismissed unread.
- **The noise report lives in three places.** A page in the app's window
  beside the history, the menu bar item's count when a sender is over its
  budget, and `snotify status`, which prints the same table. Once a day, if
  a sender crossed its budget or had nine in ten posts dismissed unread,
  Snotify posts one banner of its own, "tailscale-watch: 40 today, 38
  dismissed unread", whose click opens the page and whose Info holds the
  numbers, with Mute for today and Mute as actions.
  Decided 2026-10-11: menu bar and dashboard page, and the status command.
- **The receiver's switch always wins.** Mute per sender, mute for today,
  level cap per sender ("never more than quiet from backup.sh"), and the
  budget per sender or globally, all one config line each. Nothing a sender
  passes can raise its own budget.

## Settings

```sh
snotify config budget 5/h,20/d          # the default opening, per sender
snotify config budget backup.sh 60/m    # wide open for one sender
snotify config budget backup.sh 0       # the sender's switch, off
snotify config level backup.sh quiet    # cap what a sender may reach
snotify config mute backup.sh today     # or: on, off
snotify config expire 1h                # how long an event banner stays listed
snotify config digest 09:00,13:00,18:00
snotify config quiet 22:00-08:00
snotify status                          # the noise report, per sender, this week
snotify status --day                    # today
```

A post: `snotify --from backup.sh --level digest --title ...`, and
`snotify --clear backup.sh` to withdraw a state.

## How it works

Each post, after the tally of [sneeze.md](sneeze.md) has placed it:

1. names its sender, or is refused;
2. if the sender is muted or capped below the post's level, lowers it;
3. counts the sender's banners in the hour and the day from the history,
   and past the budget rewrites the post as the sender's overflow banner,
   same group, count and list in the body and Info;
4. a `digest` post appends to `~/.local/state/snotify/digest.md` and
   replaces the pending summary request with one for the next digest time;
5. sweeps the delivered list of expired events and of groups cleared
   since, removing them from the center;
6. writes its history file with `level`, `from`, `delivered` and, when the
   app is later relaunched by a click, a dismissal or an action, `outcome`.

The dashboard page and `snotify status` read the history files and nothing
else, per [mucus.md](mucus.md).

## Not this

- A limit on what a sender may call urgent. That is the user's.
- Dropping posts. Collapsed, expired and digested posts are all in the
  history; only the screen is thinned.
- Sound as a level. The tally carries the count, the words carry the
  meaning; see [sneeze.md](sneeze.md).
- An entitlement. Apple's time-sensitive and critical levels need one and a
  self-signed app has none, so `urgent` means "through Snotify's quiet
  hours", not through Focus.

## Open

- Whether the budget counts `banner` and `urgent` together; the marker above.
- The digest times; the marker above.
- The exact overflow banner wording and whether its Info lists the posts in
  full or by title.
- What the menu bar shows when nothing is over budget: nothing, or the
  day's count.
- Whether a `/notify` from Claude is `banner` or `urgent` by default. It
  is asked for by hand, which argues for `urgent`.
