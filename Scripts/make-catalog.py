#!/usr/bin/env python3
"""Builds catalog.json from the line data.

The catalog is everything the app needs to *talk about* a line it hasn't
downloaded: identity, colour, badge, stations for search, and the hash/size
used to decide whether an installed copy is stale.
"""
import json, hashlib, os, sys, glob, collections

ROOT = os.path.join(os.path.dirname(__file__), "..")
SCHEMA_VERSION = 1


def read_version():
    with open(os.path.join(ROOT, "VERSION")) as fh:
        return fh.read().strip()


def build():
    lines, stations = [], []
    for folder_path in sorted(glob.glob(os.path.join(ROOT, "Lines", "*", ""))):
        folder = os.path.basename(folder_path.rstrip(os.sep))
        raw = open(os.path.join(folder_path, "Line.json"), "rb").read()
        entries = json.loads(raw)
        if len(entries) != 1:
            sys.exit(f"{folder}: expected one line per folder, found {len(entries)}")
        line = entries[0]
        badges = json.load(open(os.path.join(folder_path, "Badge.json")))["lines"]
        badge = badges.get(line["id"], {})
        badge_raw = open(os.path.join(folder_path, "Badge.json"), "rb").read()

        for index, station in enumerate(line["stations"]):
            stations.append({
                "id": station["id"],
                "lineId": line["id"],
                "index": index,
                "nameJa": station.get("name", ""),
                "nameEn": station.get("nameEn", ""),
                "code": station.get("stationCode", ""),
                "lat": station.get("latitude"),
                "lon": station.get("longitude"),
            })

        lines.append({
            "id": line["id"],
            "folder": folder,
            "nameJa": line["nameJa"],
            "nameEn": line["nameEn"],
            "operatorId": line["operatorId"],
            "colorHex": line["colorHex"],
            "isLoop": line.get("isLoop", False),
            "symbol": badge.get("symbol", ""),
            "badgeStyle": badge.get("style", "jr"),
            "stationCount": len(line["stations"]),
            "bytes": len(raw) + len(badge_raw),
            "sha256": hashlib.sha256(raw).hexdigest(),
            "badgeSha256": hashlib.sha256(badge_raw).hexdigest(),
            "connects": sorted({
                t["connectingLineId"] for t in line.get("throughServices", [])
                if t.get("connectingLineId")
            }),
        })

    styles = sorted(
        os.path.splitext(os.path.basename(p))[0]
        for p in glob.glob(os.path.join(ROOT, "BadgeStyles", "*.json"))
    )
    catalog = {
        "schemaVersion": SCHEMA_VERSION,
        "version": read_version(),
        "styles": styles,
        "lines": lines,
        "stations": stations,
    }
    return catalog


def main():
    catalog = build()
    out = os.path.join(ROOT, "catalog.json")
    with open(out, "w") as fh:
        json.dump(catalog, fh, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
        fh.write("\n")

    dangling = {c for line in catalog["lines"] for c in line["connects"]} - {
        line["id"] for line in catalog["lines"]}
    size = os.path.getsize(out)
    print(f"catalog.json  {size/1024:.0f} KB  version {catalog['version']}")
    print(f"  lines {len(catalog['lines'])}  stations {len(catalog['stations'])}"
          f"  styles {len(catalog['styles'])}")
    print(f"  payload total {sum(l['bytes'] for l in catalog['lines'])/1048576:.1f} MB")
    if dangling:
        print(f"  WARNING dangling connectingLineId: {sorted(dangling)}")


if __name__ == "__main__":
    main()
