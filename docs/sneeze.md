# The sneeze: a sound that counts

Decided 2026-10-10, not built yet. This is the design, the reasons and what
is still open.

## What it is

Snotify's default sound isn't one sound. It's a tally. Posts that arrive
close together are a burst and each post in a burst plays the next step of a
sneeze building up:

| post in the burst | sound   |
| ----------------- | ------- |
| 1st               | enh     |
| 2nd               | Enh     |
| 3rd               | ENh     |
| 4th               | CHOO    |
| 5th               | enh     |

The fifth starts over.

A lone notification is an "enh" and four in a row end in a sneeze. A script
that posts on every failure in a loop makes the kid sneeze until you look,
which is the point: the poster made it loud by posting often, not by picking
a priority.

What the sound carries is the count and nothing else. People hear one, two,
three or four without counting and that's the cap. Whether a burst matters
is the convention of whoever set the script up. Importance stays with
`--color`, `--icon` and the words on the banner.

## How it works

The poster never picks. Each post:

1. reads `~/.local/state/snotify/burst.json`, the time the previous banner
   was delivered and its step, under a lock so a loop stays in order;
2. if the previous banner was delivered within the window (3 s), takes the
   next step, otherwise step 1;
3. if the previous sound hasn't finished yet, schedules its own banner with a
   time-interval trigger so the sounds play one after another instead of on
   top of each other, a few hundred milliseconds at most;
4. attaches the step's sound to the banner and writes the file back.

macOS plays the sound, as with any notification. Focus, Do Not Disturb, the
per-app sound switch and the rest of the guidelines hold, nothing in the app
stays alive and a scheduled banner is delivered by the system even after
the posting process has exited.

`--sound NAME` on a post keeps today's behaviour, a system sound or `default`,
and such a post doesn't advance the tally. A setting, `snotify config sound
sneeze|system|off`, picks the default for posts that don't say.

## The sounds

Four files in the bundle, 150 to 300 ms each, levelled with the system
sounds (peak about -13 dB). Three "enh" steps rising in pitch and the "CHOO",
in a nasal cartoon voice, synthesised in the repo so there's nothing to
licence. The voice is ours and not any studio's character so the repo never
names one.

## Not this

- A fifth, delayed "CHOO" played when a burst goes quiet. It would need the
  app to play audio itself and that ignores Focus so it was dropped.
- A sound that encodes priority. The poster has colour and glyph for that.

## Open

<!-- @Yogesh(decide): 3 s window, or longer so a slow loop (one post every 5 s) still counts as one burst? -->
- The window length.
<!-- @Yogesh(decide): does a post with --group (a replacement) advance the tally, or play the step of the banner it replaced? -->
- Replacements.
- The history records the step with the entry (`sound: "sneeze/2"`) so a
  burst can be found later.
