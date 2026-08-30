# CLAUDE.md

## Commits

Write commit messages as a **single line**. No body, no `Co-Authored-By` trailer,
no attribution of any kind.

```
Fix the Chinese names of 110 stations
Add departure platforms for ten lines
Update data
```

Detail belongs in the reply to the user, not in the message.

## Editing data

`Lines/<Line>/Line.json` is the source. After editing, bump `VERSION` and run all
three, in order:

```sh
./Scripts/format-data.swift
./Scripts/make-catalog.swift
./Scripts/validate.swift
```

`catalog.json` is generated — never hand-edit it. See `README.md` for how the app
reads the corpus and for the `schemaVersion` contract.
