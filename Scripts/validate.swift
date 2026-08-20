#!/bin/sh
//usr/bin/true; SRC="$(cd "$(dirname "$0")/.." && pwd)"
//usr/bin/true; APP="${OVERHEAD_REPO:-$SRC/../Overhead}"
//usr/bin/true; if [ ! -d "$APP/Backbone" ]; then echo "Set OVERHEAD_REPO to the Overhead checkout"; exit 1; fi
//usr/bin/true; WORK="${TMPDIR:-/tmp}/overhead-validate"; mkdir -p "$WORK"
//usr/bin/true; cp "$0" "$WORK/main.swift"
//usr/bin/true; swiftc -O -o "$WORK/validate" $(find "$APP/Backbone" -name "*.swift") "$WORK/main.swift" || exit 1
//usr/bin/true; exec "$WORK/validate" "${1:-$SRC}"
import Foundation

// Decodes every line against Backbone's real models, so a data change that the
// app could not read fails here instead of in someone's hands.

let root = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : FileManager.default.currentDirectoryPath

struct BadgeFile: Decodable { let lines: [String: LineBadgeConfig] }
var failures: [String] = []
func fail(_ message: String) { failures.append(message) }

let fm = FileManager.default
let linesRoot = "\(root)/Lines"
guard let folders = try? fm.contentsOfDirectory(atPath: linesRoot).sorted() else {
    print("no Lines directory at \(linesRoot)"); exit(1)
}

var seenIds = Set<String>()
var styleUse = Set<String>()
var connects: [(String, String)] = []
var lineCount = 0

for folder in folders {
    let dir = "\(linesRoot)/\(folder)"
    var isDir: ObjCBool = false
    guard fm.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue else { continue }

    guard let lineData = fm.contents(atPath: "\(dir)/Line.json") else {
        fail("\(folder): missing Line.json"); continue
    }
    let lines: [StaticTrainLine]
    do { lines = try JSONDecoder().decode([StaticTrainLine].self, from: lineData) }
    catch { fail("\(folder): Line.json does not decode — \(error)"); continue }

    guard lines.count == 1 else {
        fail("\(folder): holds \(lines.count) lines, expected 1"); continue
    }
    let line = lines[0]
    lineCount += 1
    if !seenIds.insert(line.id).inserted { fail("\(folder): duplicate line id \(line.id)") }

    if line.hopTimesMinutes.count != max(0, line.stations.count - 1) {
        fail("\(folder): hopTimesMinutes \(line.hopTimesMinutes.count) for \(line.stations.count) stations")
    }
    if let up = line.upHopTimesMinutes, up.count != line.hopTimesMinutes.count {
        fail("\(folder): upHopTimesMinutes length differs from hopTimesMinutes")
    }
    for through in line.throughServices {
        if let target = through.connectingLineId { connects.append((line.id, target)) }
    }

    guard let badgeData = fm.contents(atPath: "\(dir)/Badge.json") else {
        fail("\(folder): missing Badge.json"); continue
    }
    do {
        let badge = try JSONDecoder().decode(BadgeFile.self, from: badgeData)
        guard Set(badge.lines.keys) == [line.id] else {
            fail("\(folder): Badge.json covers \(badge.lines.keys.sorted()), expected \(line.id)")
            continue
        }
        styleUse.insert(badge.lines[line.id]!.style)
    } catch {
        fail("\(folder): Badge.json does not decode — \(error)")
    }
}

// Styles named by the data must exist.
let styleDir = "\(root)/BadgeStyles"
let available = Set(((try? fm.contentsOfDirectory(atPath: styleDir)) ?? [])
    .filter { $0.hasSuffix(".json") }
    .map { String($0.dropLast(5)) })
for style in styleUse.subtracting(available).sorted() {
    fail("no BadgeStyles/\(style).json, but a line asks for it")
}

// Through-services must point at lines that exist.
for (from, to) in connects where !seenIds.contains(to) {
    fail("\(from): connectingLineId \(to) matches no line")
}

// The catalog must be in step with what is on disk.
if let catalogData = fm.contents(atPath: "\(root)/catalog.json") {
    do {
        let catalog = try JSONDecoder().decode(LineCatalog.self, from: catalogData)
        let catalogIds = Set(catalog.lines.map(\.id))
        for missing in seenIds.subtracting(catalogIds).sorted() {
            fail("catalog.json is missing \(missing) — re-run make-catalog.py")
        }
        for extra in catalogIds.subtracting(seenIds).sorted() {
            fail("catalog.json lists \(extra), which is not on disk")
        }
        for style in Set(catalog.styles).symmetricDifference(available).sorted() {
            fail("catalog.json style list disagrees on \(style)")
        }
    } catch {
        fail("catalog.json does not decode — \(error)")
    }
} else {
    fail("no catalog.json — run make-catalog.py")
}

if failures.isEmpty {
    print("OK  \(lineCount) lines, \(styleUse.count) styles in use, \(connects.count) through-services")
    exit(0)
}
print("\(failures.count) problem(s):")
for f in failures { print("  \(f)") }
exit(1)
