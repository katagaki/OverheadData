#!/bin/sh
//usr/bin/true; SRC="$(cd "$(dirname "$0")/.." && pwd)"
//usr/bin/true; WORK="${TMPDIR:-/tmp}/overhead-format-data"; mkdir -p "$WORK"
//usr/bin/true; cp "$0" "$WORK/main.swift"
//usr/bin/true; swiftc -O -o "$WORK/format-data" "$SRC/Scripts/JSONFormat.swift" "$WORK/main.swift" || exit 1
//usr/bin/true; exec "$WORK/format-data" "${1:-$SRC}"
import Foundation

// Rewrites the hand-authored data in the house style: keys sorted, 4-space
// indent, arrays of scalars on one line. Run it after editing by hand or by
// script, so a data diff shows what changed rather than how it was written.

let root = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : FileManager.default.currentDirectoryPath
let fm = FileManager.default

var targets: [String] = []
let linesRoot = (root as NSString).appendingPathComponent("Lines")
for folder in ((try? fm.contentsOfDirectory(atPath: linesRoot)) ?? []).sorted() {
    let dir = (linesRoot as NSString).appendingPathComponent(folder)
    for file in ["Line.json", "Badge.json"] {
        let path = (dir as NSString).appendingPathComponent(file)
        if fm.fileExists(atPath: path) { targets.append(path) }
    }
}
for file in ["Operators.json", "Segments.json"] {
    let path = (root as NSString).appendingPathComponent(file)
    if fm.fileExists(atPath: path) { targets.append(path) }
}

var rewritten = 0
var failed: [String] = []
for path in targets {
    guard let data = fm.contents(atPath: path),
          let value = try? JSONFormat.read(data) else {
        failed.append(path)
        continue
    }
    let text = JSONFormat.pretty(value) + "\n"
    let before = String(data: data, encoding: .utf8)
    if before != text {
        try? text.write(toFile: path, atomically: true, encoding: .utf8)
        rewritten += 1
    }
}

print("formatted \(targets.count) files, rewrote \(rewritten)")
if !failed.isEmpty {
    FileHandle.standardError.write(Data(("unreadable:\n  "
        + failed.joined(separator: "\n  ") + "\n").utf8))
    exit(1)
}
