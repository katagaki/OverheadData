# OverheadData

Timetable and badge data for [Overhead](https://github.com/katagaki/Overhead).

## Editing

Edit `Lines/<Line>/Line.json`, bump `VERSION` to name the release, then:

```sh
./Scripts/format-data.swift    # house style: sorted keys, scalar arrays on one line
./Scripts/make-catalog.swift   # regenerate the catalog
./Scripts/validate.swift       # decode everything against the app's models
```

`validate.swift` compiles the app's real models, so it needs an `Overhead`
checkout beside this one (or `OVERHEAD_REPO` pointing at it). CI runs all three
on every push, so a file the app could not read fails there rather than on a
phone.

## How the app reads it

`catalog.json` is fetched with a conditional GET, so an unchanged check costs a
304 and no body. Lines download individually and are verified against their
`sha256` in the catalog — which is also what decides staleness, not `VERSION`.
The corpus is ~1.2 MB gzipped, the catalog ~86 KB.

## Schema changes

`schemaVersion` in `catalog.json` is the contract between the data and the app.

**Additive changes need no bump** — a new optional key, badge style, or segment
is ignored by older builds. Every field added since v1 is optional for this
reason.

**Breaking changes** — a renamed, removed, or redefined key — bump it, and in
the same release freeze the last compatible generation under `legacy/v<old>/`:
`catalog.json` (with `"dataPath": "legacy/v<old>/"`) plus the `Lines/` and
`BadgeStyles/` trees as they stood.

An old build then sees a schema it cannot read, pins itself to that legacy
catalog, shows 「アプリの更新が必要です」, and goes on working with frozen data
instead of silently rotting. New builds read the root catalog and never look at
`legacy/`.
