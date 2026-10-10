# The sneeze: a sound that counts

Decided 2026-10-10, not built yet. This is the design, the reasons, the
decisions taken and what is still open.

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

What the sound carries is the count and nothing else. Whether a burst
matters is the convention of whoever set the script up. Importance stays
with `--color`, `--icon` and the words on the banner.

## Decisions

- **On by default.** A post without `--sound` plays the tally. Today it's
  silent so every script that never asked for a sound starts making one,
  and `snotify config sound off` is the one line that stops it.
- **Until the sneeze exists the default is `Glass@35,Glass@70,Glass`**, two
  cut plays of a system sound and a whole one, the way old Windows error
  sounds stacked and only the last played out. Nothing to synthesise and
  nothing to licence.
- **A replacement advances the tally.** A `--group` post that replaces a
  banner is still a thing that happened. It may get its own flavour of the
  step, a sneeze that doesn't come so the listener knows a banner was
  swapped and not added; open until the sounds exist.
- **The Claude Code hook joins the tally.** It drops its own `--sound Glass`
  so Claude's banners count like everything else.
- **An explicit `--sound` doesn't advance the tally but is still spaced**,
  so it never lands on top of a tally sound. The spacing is about hearing,
  not counting.
- **Window 3 s, spacing 500 ms, burst limit 20 s.** The evidence is below.
- **The history records the burst, not the sound.** Which file played is
  worth nothing later. Which posts made one burst, how far apart they were
  and from where is what someone with a heavy stream wants to see, the
  difference between a long-term holder and an intraday trader looking at
  the same ticker. Each entry gets `burst` (the id of the burst's first
  entry) and `burst_step` and the journal view in the backlog groups on
  them.

## Settings

```sh
snotify config sound sniffles          # buildup | sniffles | system | off | a list
snotify config sound Glass@35,Glass@70,Glass   # your own sequence, by name
snotify config sound-window 3s         # quiet that ends a burst
snotify config sound-burst 20s         # the longest one burst can run before it starts over
snotify config sound-spacing 500ms     # least time between two sound onsets
```

A list is any sounds by name, the bundle first, then `~/Library/Sounds`,
then `/System/Library/Sounds` so `Glass,Glass,Glass,Basso` is a tally in
system sounds. `NAME@35` is the first 35 % of that sound with a short fade;
the app writes the cut file into `~/Library/Sounds` under a `snotify-`
prefix on first use and the system plays it like any other and they're
easy to find and delete. `system` is today's behaviour, the macOS default
sound on every post.

<!-- @Yogesh(check): window = quiet that ends a burst, burst = longest one burst can run; is that the pair you meant by "duration of burst" and "duration of gap"? -->
The window is the quiet after a post that ends the burst. The burst limit is
for a script that posts every two seconds for a minute: without it that's
one burst going round the sequence fifteen times and with it the count
starts again every twenty seconds.

## The durations, and why

Researched on 2026-10-10, the sources in the links.

- **Window, 3 s.** The best-supported number. Pöppel's integration window
  puts the "subjective present" at 2 to 3 s and at a 5 s gap two sounds no
  longer join into one percept
  ([Pöppel 2004](https://ane.pl/index.php/ane/article/download/1514/1514)).
  The musical limit is stricter, past about 2 s a listener stops hearing a
  beat ([London, Hearing in Time](https://academic.oup.com/book/9899)). So
  3 s is the latest gap at which the next sound still reads as the same
  thing continuing and it tolerates a script posting every 2 s with jitter.
  Not above 3 s.
- **Spacing, 500 ms between onsets.** Perception sets the floor far lower,
  two clicks separate at a few ms and people count events accurately up to
  8 per second so the floor that matters is rhythm: beats are heard as one
  figure down to about 100 ms apart. The one industry figure is Android's
  limit of one alert sound per second per app and it drops the extra rather
  than delaying it
  ([Android 8.1 notes](https://developer.android.com/about/versions/oreo/android-8.1)).
  500 ms keeps the tally a rhythm and lets a sound of 350 ms finish first.
- **Burst limit, 20 s, a judgment call.** Nothing in the literature works
  at this scale, batching research is in minutes and hours and game combos
  reset on a miss, not a timer. Two weak anchors: Android's lowest toast
  tier is 3 per 20 s and at 2 s spacing a cycle of four is 8 s so 20 s is
  about two and a half cycles.
- **A caveat on counting.** Sequential sounds are subitised only up to two
  ([Camos and Tillmann 2008](https://researchers.westernsydney.edu.au/en/publications/discontinuity-in-the-enumeration-of-sequentially-presented-audito/)),
  the "four without counting" figure is for things seen at once. So the
  steps must not rely on being counted: each one has to be recognisable on
  its own, by pitch or by how much of the sound played.
- **Lengths.** The system sounds run 0.56 s (Tink) to 2.16 s with their
  tails, Glass is 1.65 s, Slack's knock is 0.55 s, Apple's Tri-tone 0.9 s.
  A tally in whole Glass would be slow and that is one more reason the cut
  versions make a better default than the whole sound.

## How it works

The poster never picks. Each post:

1. reads `~/.local/state/snotify/burst.json`, the time the previous banner
   was delivered, its step and the burst's start, under a lock so a loop
   stays in order;
2. if the previous banner was delivered within the window and the burst is
   under its limit, takes the next sound of the sequence, otherwise the
   first;
3. if the previous onset is less than the spacing ago, schedules its own
   banner with a time-interval trigger for the difference so the sounds
   play one after another instead of on top of each other;
4. attaches the step's sound to the banner and writes the file back.

macOS plays the sound, as with any notification. Focus, Do Not Disturb, the
per-app sound switch and the rest of the guidelines hold, nothing in the app
stays alive and a scheduled banner is delivered by the system even after
the posting process has exited.

## A spec for the sounds

So that anyone can make a set, with a synthesiser, a microphone or a
generative model, and drop it into the sequence by name:

- **Four to a set**, one per step and a set is one voice or one instrument
  throughout.
- **Length 150 to 400 ms** for a step, up to 700 ms for a sneeze. The
  spacing is 500 ms so a step must be over before the next can start.
- **Level: peak about -13 dB**, where the macOS system sounds sit and no
  louder than Glass at any point.
- **Each step recognisable on its own.** A listener hearing only the third
  sound should know it's the third: rising pitch across the set, or more of
  the same sound played each time, or both. Don't count on the listener
  having heard the earlier ones.
- **Natural over clever.** The build-up should feel like one thing getting
  closer, not four unrelated sounds and the last step is the release. A
  sneeze does this on its own, which is why it was chosen.
- **A replacement flavour is optional**: the same step, shorter or cut off,
  for a banner that replaced another.
- **Format**: AIFF or CAF, 44.1 kHz, mono is fine. Under 30 s or macOS
  plays the default instead.
- **Licence**: made by you or CC0, since the file ships in an MIT repo.

The shipped sets, `buildup` and `sniffles`, follow this spec and are
synthesised in the repo so there's nothing to licence. The voice is ours and
not any studio's character so the repo never names one.

## Not this

- A fifth, delayed "CHOO" played when a burst goes quiet. It would need the
  app to play audio itself and that ignores Focus so it was dropped.
- A sound that encodes priority. The poster has colour and glyph for that.
- Recording the sound in the history. Low value, see Decisions.

## Open

- The replacement flavour, once the sounds exist.
- The sounds themselves. The mechanism ships first on the cut Glass default.
