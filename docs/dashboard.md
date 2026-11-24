<!-- @Yogesh(name): dashboard.md is a placeholder; the other docs are mucus, sneeze, congestion, tissue -->
<!-- @Yogesh(check): Claude's draft from the 2026-11-24 conversation, in Claude's words, from your "analytics dashboard for snotify UI" message; rewrite it or keep it -->
# Dashboard: what the history says when you count it

Decided 2026-11-24, not built yet. This is the plan for the analytics
dashboard and for the noise report [congestion.md](congestion.md) promised,
which are the same count over the history files, cut by time
and by sender, with the same numbers in the window and on the command line.

## Decided 2026-11-24

- **The dashboard and the noise report are built together.** The report is a
  preset of the dashboard so there's one engine and one set of numbers.
- **The CLI's JSON is the API.** `snotify stats --json` and
  `snotify history --json`, plus the files themselves. No server, no socket,
  nothing new running, per [mucus.md](mucus.md).
- **One query language everywhere.** The search field, `snotify history`,
  `snotify show`, `snotify stats` and `snotify status` all parse the same
  words the same way. A repeated key ORs, different keys AND.
- **`snotify stats` is the engine and `snotify status` is its preset.**
  `status` prints the per-sender noise table congestion.md describes.
- **Expiry and delivery get recorded from now on.** Without them the report
  can't tell a banner nobody saw from one somebody ignored.
- **macOS gets the window first.** The query and the CLI land on both builds
  in the same change and the Linux window follows.
- Budgets, mute, levels, quiet hours and the daily over-budget banner stay in
  congestion.md and aren't part of this.

## The query

Today every word has to match so `from:backup.sh from:ci` matches nothing.
The new rules:

| Words | Means |
| --- | --- |
| `from:backup.sh from:ci` | from either |
| `from:ci outcome:clicked` | from ci and clicked |
| `-from:ci` | anyone but ci |
| `has:outcome.clicked` | the field exists, whatever its value |
| `-has:outcome.clicked` | never clicked |
| `deploy failed` | both words somewhere in the entry, as today |

A key still matches its full dotted name or its last part (`process:bash`
finds `sender.process`), values still match as a substring and case is still
ignored. Words without a key keep matching the whole entry.

<!-- @Yogesh(decide): `from:` matches the `from` field only, so a post sent without --from never matches `from:bash` even though the sidebar shows it as bash; make `from:` match the shown sender (`from`, else `sender.process`)? -->

The time range stays out of the query and in flags:
`--since 7d|36h|2026-11-01|2026-11-01T09:00` and the same forms for a new
`--until`. In the window the calendar sets it and a from and to time can be
typed for a span shorter than a day.

## `snotify stats`

```sh
snotify stats [QUERY...] [--since 7d] [--until DATE] \
              [--by hour|day|week|month] [--group from|outcome|host|KEY] \
              [--json | --csv]
snotify status [--day]          # stats --group from --since 7d, the noise columns
```

Without `--json` it prints a table. `--csv` prints the buckets, one row per
bucket and group, for a spreadsheet. `--json` prints everything the window
draws:

```json
{
  "query": "from:backup.sh from:ci",
  "since": "2026-11-17T00:00:00+05:30",
  "until": "2026-11-24T23:59:59+05:30",
  "by": "day",
  "group": "from",
  "complete_since": "2026-11-25T10:12:00+05:30",
  "buckets": [
    {"start": "2026-11-24T00:00:00+05:30", "counts": {"backup.sh": 3, "ci": 11}}
  ],
  "groups": [
    {"name": "ci", "posted": 11, "delivered": 11, "clicked": 2,
     "info_opened": 1, "dismissed_unread": 6, "expired": 2, "replaced": 0,
     "react_seconds": {"p50": 14, "p90": 210}}
  ],
  "weekday_hour": [[0, 0, 1, "... 24 per row, Monday first"]],
  "gaps_seconds": {"ci": {"p10": 4, "p50": 600, "p90": 7200}},
  "bursts": [{"group": "ci", "start": "2026-11-24T10:02:11+05:30", "count": 9}]
}
```

The numbers in that example are made up to show the shape.

- **posted** is every entry that matched. **delivered** has a `delivered`
  field. **dismissed_unread** was dismissed or cleared with no
  `outcome.clicked` and no `outcome.info_opened`. **replaced** has
  `outcome.replaced_by`.
- **react_seconds** is the time from `time` to the first `outcome.*`
  timestamp, per group.
- **gaps_seconds** is the time between consecutive posts from one sender.
- **bursts** is a sender posting at least N times inside M minutes.
  <!-- @Yogesh(number): what N and M make a burst? 5 in 10 minutes is a guess -->
- **complete_since** is the first entry that carries `delivered`. Counts
  before it can't separate missed from ignored and the window says so over
  those days.

Both builds print the same JSON for the same directory and the test checks
that byte for byte on a fixture history.

## What gets recorded

What's in the files today, checked 2026-11-24:

| | macOS | Linux |
| --- | --- | --- |
| clicked | `outcome.clicked` | `outcome.clicked` |
| Info opened | `outcome.info_opened` | `outcome.info_opened` |
| dismissed | only for posts with Info: `customDismissAction` is set on the Info category alone (`Sources/main.swift:604`) | `outcome.dismissed` |
| cleared from the tray | n/a | `outcome.cleared` |
| expired | n/a, a banner goes to Notification Center | nothing, `expire()` removes the card silently (`linux/snotify-app:1488`) |
| replaced by its group | `outcome.replaced_by` | `outcome.replaced_by` |
| reached the screen | nothing | nothing |

The changes:

- **macOS** puts every post in a category with `customDismissAction`: the Info
  category when there's Info, a new plain one without actions otherwise. A
  dismissal, and "clear all" as a dismissal of each, is then recorded for
  every post.
- **macOS** writes `delivered` when `UNUserNotificationCenter.add` completes
  without an error.
- **Linux** writes `outcome.expired` in `expire()` and `delivered` when the card
  is shown or `notify-send` exits 0.

Neither change touches a file that's already there. Old entries count as
posted with unknown delivery.

## The window

A List and Stats switch in the History window's toolbar. Stats keeps the
search field, the calendar and the sender facets so the selection carries
across, and draws, top to bottom:

1. posts per bucket, stacked by group, with the bucket size picked from the
   range (hours for a day, days for a month) unless changed;
2. the noise table, one row per sender, the `snotify status` columns, sorted
   by dismissed unread;
3. the weekday and hour heatmap;
4. time to react per sender, median and 90th percentile;
5. gaps and bursts, the bursts listed and clickable back to the List with
   their range selected.

A click on a bar or a cell narrows the calendar or the query to it. Swift
Charts in an `NSHostingView`, the app's first SwiftUI, which the
`LSMinimumSystemVersion` 13.0 already allows; the build adds
`-framework SwiftUI -framework Charts`. It refreshes from the file watch the
window already has so nothing wakes on a timer.

`--snapshot` learns the Stats view and `just preview out.png --stats` renders
it over the synthesised history for review.

<!-- @Yogesh(number): how long does a full reload of the 523 files in your history take? not measured yet, and it decides whether the window needs anything cleverer than reading them all -->

## Not this

- A database, an index or a cache file next to the history. The stats are
  read from the Markdown every time, per mucus.md.
- An HTTP endpoint. If one comes later it serves this JSON unchanged.
- Budgets, mutes, levels and the over-budget banner. congestion.md.
- Exporting to Grafana or anything else. `--json` and `--csv` are the export.

## Build order

1. The query rules in `History.swift` and `linux/snotify-app`, with fixture
   tests in `scripts/snotify-app-test.sh` for each row of the table above.
2. The recording changes on both builds.
3. `snotify stats` and `snotify status`, table, JSON and CSV, on both
   builds and the parity test on compute2 via `just linux test`.
4. The Stats view on macOS, `--snapshot` and `just preview --stats`.
5. README, CHANGELOG and a pointer from congestion.md's noise report to here.
6. The Stats view in the Linux window.

## Open

- What the burst threshold is, the marker above.
- Whether `from:` should match the shown sender, the marker above.
- Whether `status` sorts by dismissed unread or by posted.
- Whether the Stats view remembers its bucket size per range or resets.
