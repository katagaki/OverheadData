#!/bin/sh
//usr/bin/true; SRC="$(cd "$(dirname "$0")/.." && pwd)"
//usr/bin/true; WORK="${TMPDIR:-/tmp}/overhead-make-catalog"; mkdir -p "$WORK"
//usr/bin/true; cp "$0" "$WORK/main.swift"
//usr/bin/true; swiftc -O -o "$WORK/make-catalog" "$SRC/Scripts/JSONFormat.swift" "$WORK/main.swift" || exit 1
//usr/bin/true; exec "$WORK/make-catalog" "${1:-$SRC}"
import Foundation
import CryptoKit

// Builds catalog.json from the line data.
//
// The catalog is everything the app needs to *talk about* a line it hasn't
// downloaded: identity, colour, badge, stations for search, and the hash/size
// used to decide whether an installed copy is stale.

let schemaVersion = 2

let root = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : FileManager.default.currentDirectoryPath
let fm = FileManager.default

func die(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func path(_ parts: String...) -> String {
    parts.reduce(root) { ($0 as NSString).appendingPathComponent($1) }
}

func read(_ file: String) -> Data {
    guard let data = fm.contents(atPath: file) else { die("missing \(file)") }
    return data
}

func json(_ file: String) -> JSONFormat.Value {
    guard let value = try? JSONFormat.read(read(file)) else { die("unreadable \(file)") }
    return value
}

// MARK: - Value access

extension JSONFormat.Value {
    subscript(key: String) -> JSONFormat.Value? {
        guard case .object(let pairs) = self else { return nil }
        return pairs.first { $0.0 == key }?.1
    }
    var items: [JSONFormat.Value] {
        guard case .array(let a) = self else { return [] }
        return a
    }
    var text: String {
        guard case .string(let s) = self else { return "" }
        return s
    }
    var flag: Bool {
        guard case .bool(let b) = self else { return false }
        return b
    }
}

func obj(_ pairs: [(String, JSONFormat.Value)]) -> JSONFormat.Value {
    .object(pairs.sorted { $0.0 < $1.0 })
}

// MARK: - Inputs

let version = String(decoding: read(path("VERSION")), as: UTF8.self)
    .trimmingCharacters(in: .whitespacesAndNewlines)

func listing(_ directory: String, extension ext: String) -> [String] {
    let dir = path(directory)
    guard let names = try? fm.contentsOfDirectory(atPath: dir) else { return [] }
    return names
        .filter { ($0 as NSString).pathExtension == ext }
        .map { ($0 as NSString).deletingPathExtension }
        .sorted()
}

func section(_ file: String, _ key: String) -> [JSONFormat.Value] {
    let full = path(file)
    guard fm.fileExists(atPath: full) else { return [] }
    return json(full)[key]?.items ?? []
}

let segments = section("Segments.json", "segments")
let operators = section("Operators.json", "operators")

// MARK: - Lines

var lines: [JSONFormat.Value] = []
var stations: [JSONFormat.Value] = []

let folders = ((try? fm.contentsOfDirectory(atPath: path("Lines"))) ?? [])
    .filter { !$0.hasPrefix(".") }
    .sorted()

for folder in folders {
    let linePath = path("Lines", folder, "Line.json")
    let badgePath = path("Lines", folder, "Badge.json")
    let lineRaw = read(linePath)
    let badgeRaw = read(badgePath)

    guard let parsed = try? JSONFormat.read(lineRaw) else { die("\(folder): unreadable Line.json") }
    let entries = parsed.items
    guard entries.count == 1 else {
        die("\(folder): expected one line per folder, found \(entries.count)")
    }
    let line = entries[0]
    let id = line["id"]!.text

    let badges = json(badgePath)["lines"]
    let badge = badges?[id]

    let lineStations = line["stations"]?.items ?? []
    for (index, station) in lineStations.enumerated() {
        stations.append(obj([
            ("id", station["id"] ?? .string("")),
            ("lineId", .string(id)),
            ("index", .int(index)),
            ("name", station["name"] ?? .object([])),
            ("code", station["stationCode"] ?? .string("")),
            ("lat", station["latitude"] ?? .null),
            ("lon", station["longitude"] ?? .null),
        ]))
    }

    let connects = Set((line["throughServices"]?.items ?? []).compactMap { service -> String? in
        let value = service["connectingLineId"]?.text ?? ""
        return value.isEmpty ? nil : value
    }).sorted()

    func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    var entry: [(String, JSONFormat.Value)] = [
        ("id", .string(id)),
        ("folder", .string(folder)),
        ("name", line["name"] ?? .object([])),
        ("operatorId", line["operatorId"] ?? .string("")),
        ("colorHex", line["colorHex"] ?? .string("")),
        ("isLoop", .bool(line["isLoop"]?.flag ?? false)),
        ("symbol", badge?["symbol"] ?? .string("")),
        ("badgeStyle", badge?["style"] ?? .string("jr")),
        ("stationCount", .int(lineStations.count)),
        ("bytes", .int(lineRaw.count + badgeRaw.count)),
        ("sha256", .string(digest(lineRaw))),
        ("badgeSha256", .string(digest(badgeRaw))),
        ("connects", .array(connects.map { .string($0) })),
    ]
    if let segment = line["segment"]?.text, !segment.isEmpty {
        entry.append(("segment", .string(segment)))
    }
    lines.append(obj(entry))
}

// MARK: - Checks

let knownSegments = Set(segments.map { $0["id"]?.text ?? "" })
let knownOperators = Set(operators.map { $0["id"]?.text ?? "" })
for line in lines {
    let folder = line["folder"]?.text ?? "?"
    if let segment = line["segment"]?.text, !segment.isEmpty,
       !knownSegments.contains(segment) {
        die("\(folder): unknown segment \(segment)")
    }
    let operatorId = line["operatorId"]?.text ?? ""
    if !knownOperators.isEmpty, !knownOperators.contains(operatorId) {
        die("\(folder): unknown operator \(operatorId)")
    }
}

// MARK: - Output

let styles = listing("BadgeStyles", extension: "json")
// Curated operator marks, for the operators whose sites have no usable
// favicon. Named by operator id with ":" swapped for "_".
let operatorIcons = listing("OperatorIcons", extension: "png")

let catalog = obj([
    ("schemaVersion", .int(schemaVersion)),
    ("version", .string(version)),
    ("styles", .array(styles.map { .string($0) })),
    ("operatorIcons", .array(operatorIcons.map { .string($0) })),
    ("segments", .array(segments)),
    ("operators", .array(operators)),
    ("lines", .array(lines)),
    ("stations", .array(stations)),
])

let out = path("catalog.json")
try! (JSONFormat.compact(catalog) + "\n").write(toFile: out, atomically: true, encoding: .utf8)

let lineIds = Set(lines.map { $0["id"]?.text ?? "" })
let dangling = Set(lines.flatMap { ($0["connects"]?.items ?? []).map(\.text) })
    .subtracting(lineIds)
let size = ((try? fm.attributesOfItem(atPath: out))?[.size] as? Int) ?? 0
let payload = lines.reduce(0) { total, line -> Int in
    guard case .int(let bytes)? = line["bytes"] else { return total }
    return total + bytes
}

print(String(format: "catalog.json  %.0f KB  version %@", Double(size) / 1024, version))
print("  lines \(lines.count)  stations \(stations.count)"
      + "  styles \(styles.count)  operator icons \(operatorIcons.count)")
print(String(format: "  payload total %.1f MB", Double(payload) / 1_048_576))
if !dangling.isEmpty {
    print("  WARNING dangling connectingLineId: \(dangling.sorted())")
}
