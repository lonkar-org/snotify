# The sneeze: a sound that counts

Decided 2026-10-10, not built yet. This is the design, the reasons and what
is still open.

## What it is

Snotify's default sound isn't one sound. It's a tally. Posts that arrive
close together are a burst and each post in a burst plays the next sound of
a sequence, round and round. Two sequences ship and the user picks, or
writes their own:

| post in the burst | `buildup` | `sniffles` |
| ----------------- | --------- | ---------- |
| 1st               | enh       | ah-CHOO    |
| 2nd               | Enh       | snf        |
| 3rd               | ENh       | SNf        |
| 4th               | CHOO      | SNF        |
| 5th               | enh       | ah-CHOO    |

`buildup` is the sneeze coming: a lone notification is one "enh" and four in
a row end in the sneeze. `sniffles` is the sneeze first and the sniffing
after it: a lone notification is the sneeze and the count is in the sniffs.
A script that posts on every failure in a loop makes the kid sneeze until
you look, which is the point: the poster made it loud by posting often, not
by picking a priority.

What the sound carries is the count and nothing else. People hear one, two,
three or four without counting and that's the cap. Whether a burst matters
is the convention of whoever set the script up. Importance stays with
`--color`, `--icon` and the words on the banner.

## Settings

```sh
snotify config sound sniffles          # buildup | sniffles | system | off | a list
snotify config sound achoo,Glass,Pop   # your own sequence: bundled or system sounds by name
snotify config sound-window 3s         # quiet that ends a burst
snotify config sound-burst 20s         # the longest one burst can run before it starts over
```

A list is any sounds by name, bundled ones first and `/System/Library/Sounds`
after, so `Glass,Glass,Glass,Basso` is a tally in system sounds. `system`
is today's behaviour, the macOS default sound on every post. The window is
the quiet after a post that ends the burst. The burst limit is for a script
that posts every two seconds for a minute: without it that's one burst
going round the sequence fifteen times and with it the count starts again
every twenty seconds.

## How it works

The poster never picks. Each post:

1. reads `~/.local/state/snotify/burst.json`, the time the previous banner
   was delivered and its step, under a lock so a loop stays in order;
2. if the previous banner was delivered within the window and the burst is
   under its limit, takes the next sound of the sequence, otherwise the
   first;
3. if the previous sound hasn't finished yet, schedules its own banner with a
   time-interval trigger so the sounds play one after another instead of on
   top of each other, a few hundred milliseconds at most;
4. attaches the step's sound to the banner and writes the file back.

macOS plays the sound, as with any notification. Focus, Do Not Disturb, the
per-app sound switch and the rest of the guidelines hold, nothing in the app
stays alive and a scheduled banner is delivered by the system even after
the posting process has exited.

`--sound NAME` on a post keeps today's behaviour, a system sound or `default`,
and such a post doesn't advance the tally.

## The sounds

Eight files in the bundle, 150 to 400 ms each, levelled with the system
sounds (peak about -13 dB): three "enh" steps rising in pitch, the "CHOO" on
its own, the full "ah-CHOO", and three sniffs rising. All in one nasal
cartoon voice, synthesised in the repo so there's nothing to licence. The
voice is ours and not any studio's character so the repo never names one.

## Not this

- A fifth, delayed "CHOO" played when a burst goes quiet. It would need the
  app to play audio itself and that ignores Focus so it was dropped.
- A sound that encodes priority. The poster has colour and glyph for that.

## Open

<!-- @Yogesh(check): window = quiet that ends a burst, burst = longest one burst can run; is that the pair you meant by "duration of burst" and "duration of gap"? -->
- The two durations and their defaults, 3 s and 20 s.
<!-- @Yogesh(decide): does a post with --group (a replacement) advance the tally, or play the step of the banner it replaced? -->
- Replacements.
- The history records the step with the entry (`sound: "sniffles/2"`) so a
  burst can be found later.
