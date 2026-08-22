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

Edit `Lines/<Line>/Line.json`, bump `VERSION` if you want the release named,
then:

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

`VERSION` names the release and is shown in the app; the app decides what to
re-download from the per-line `sha256` in the catalog, not from the version.

## Schema changes

`schemaVersion` in `catalog.json` is the contract between the data and the app.

**Additive changes need no bump.** New optional keys on a line, a new badge
style, a new segment: older builds decode the files and ignore what they do not
know. Every model field the app added since v1 is optional for this reason.

**Breaking changes bump it** — a renamed or removed key, or one whose meaning
changes. Then, in the same release:

1. Freeze the last compatible generation under `legacy/v<old>/`: `catalog.json`
   (with `"dataPath": "legacy/v<old>/"`) plus the `Lines/` and `BadgeStyles/`
   trees as they stood.
2. Publish the new generation at the root with the higher `schemaVersion`.

An old build fetches the root catalog, sees a schema it cannot read, pins
itself to `legacy/v<old>/catalog.json`, and keeps downloading from the path
that catalog names. It shows 「アプリの更新が必要です」 and goes on working with
the frozen data instead of silently rotting. A build that understands the new
schema reads the root catalog and never looks at `legacy/`.
