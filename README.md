# OverheadData

Timetable and badge data for [Overhead](https://github.com/katagaki/Overhead).
The app downloads lines from this repository, so **a push here reaches users
without an App Store release**.

```
Lines/<Line>/Line.json      one line per folder: stations, hop times, timetables
             Badge.json     which badge style that line uses
BadgeStyles/<style>.json    how each operator's plate is drawn
catalog.json                generated — every line and station, with sizes and hashes
Scripts/
```

## Editing

Edit `Lines/<Line>/Line.json`, then:

```sh
python3 Scripts/make-catalog.py   # regenerate the catalog
./Scripts/validate.swift          # decode everything against the app's models
```

`validate.swift` compiles the app's real model code, so it needs an `Overhead`
checkout beside this one (or `OVERHEAD_REPO` pointing at it). CI runs both on
every push; a file the app could not read fails there rather than on a phone.

Keep scalar arrays on one line (`"hopTimesMinutes": [2, 2, 3]`) — that is what
`Scripts/jsonfmt.py` produces, and it keeps diffs and downloads small.

## How the app reads it

`catalog.json` is fetched with a conditional GET, so an unchanged check costs a
304 and no body. Lines are downloaded individually and verified against the
`sha256` in the catalog. The whole corpus is ~1.2 MB gzipped; the catalog alone
is ~86 KB.

Bumping `schemaVersion` retires older app builds gracefully: they ignore a
catalog they do not understand and keep what they already have.
