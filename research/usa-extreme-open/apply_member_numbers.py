#!/usr/bin/env python3
"""Apply a member-number-review.csv onto the MIFFs in the same directory.

Blank or INC memberNumber cells share one synthetic number per normalized name.
IGNORE leaves the shooter unchanged. Any other value is written as memberNumber,
and knownMemberNumbers is set to that value alone so Practiscore bibs are not
kept as identities.

  python3 apply_member_numbers.py [review-directory] [first-synthetic]
"""

import csv
import gzip
import json
import re
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parent
REVIEW = ROOT / "member-number-review.csv"
SOURCE_DIR = ROOT / "miff"
OUT_DIR = ROOT / "miff-with-members"
SYNTHETIC_LOG = ROOT / "synthetic-member-numbers.csv"
FIRST_SYNTHETIC = int(sys.argv[2]) if len(sys.argv) > 2 else 1000025

def name_key(name: str) -> str:
    collapsed = re.sub(r"\s+", "", name.lower())
    return "".join(ch for ch in collapsed if ch.isalnum())


def normalize_number(number: str) -> str:
    return re.sub(r"[^A-Z0-9]", "", number.upper())


def load_review():
    with REVIEW.open(newline="") as handle:
        return list(csv.DictReader(handle))


def assign_synthetics(rows):
    groups = defaultdict(list)
    for row in rows:
        token = (row["memberNumber"] or "").strip()
        if token.upper() in ("", "INC"):
            groups[name_key(row["name"])].append(row)
    assigned = {}
    number = FIRST_SYNTHETIC
    for key in sorted(groups):
        assigned[key] = f"F{number}"
        number += 1
    return assigned, groups


def decision_for(row, synthetics):
    token = (row["memberNumber"] or "").strip()
    upper = token.upper()
    if upper == "IGNORE":
        return None
    if upper in ("", "INC"):
        return synthetics[name_key(row["name"])]
    return normalize_number(token)


def main():
    rows = load_review()
    synthetics, groups = assign_synthetics(rows)
    by_shooter = {}
    for row in rows:
        key = (row["match"], int(row["entryId"]))
        if key in by_shooter:
            sys.exit(f"Duplicate review row for {key}")
        by_shooter[key] = decision_for(row, synthetics)

    OUT_DIR.mkdir(exist_ok=True)
    applied = {"explicit": 0, "synthetic": 0, "unchanged": 0}

    for source in sorted(SOURCE_DIR.glob("*.miff.gz")):
        document = json.loads(gzip.open(source).read())
        match = document["match"]
        seen = set()
        for shooter in match["shooters"]:
            key = (match["name"], shooter["id"])
            if key not in by_shooter:
                sys.exit(f"No review row for {key[0]} id {key[1]} {shooter['firstName']} {shooter['lastName']}")
            seen.add(key)
            number = by_shooter[key]
            if number is None:
                applied["unchanged"] += 1
                continue
            shooter["memberNumber"] = number
            shooter["knownMemberNumbers"] = [number]
            shooter.pop("originalMemberNumber", None)
            if number in synthetics.values():
                applied["synthetic"] += 1
            else:
                applied["explicit"] += 1
        missing = [key for key in by_shooter if key[0] == match["name"] and key not in seen]
        if missing:
            sys.exit(f"Review rows with no shooter in {match['name']}: {missing[:5]}")
        target = OUT_DIR / source.name
        with gzip.open(target, "wt", encoding="utf-8") as handle:
            json.dump(document, handle, ensure_ascii=False, separators=(",", ":"))
        print(f"Wrote {target} ({len(match['shooters'])} shooters)")

    with SYNTHETIC_LOG.open("w", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(["syntheticNumber", "name", "matches"])
        for key in sorted(groups, key=lambda item: synthetics[item]):
            sample = groups[key]
            names = sorted({row["name"] for row in sample})
            matches = sorted({f"{row['match'][-4:]} {row['division']}" for row in sample})
            writer.writerow([synthetics[key], " | ".join(names), "; ".join(matches)])

    highest = FIRST_SYNTHETIC + len(groups) - 1 if groups else FIRST_SYNTHETIC - 1
    print(f"Explicit numbers: {applied['explicit']}")
    print(f"Synthetic rows: {applied['synthetic']}")
    print(f"Unchanged rows: {applied['unchanged']}")
    print(f"Synthetic names: {len(groups)}")
    print(f"Highest synthetic: F{highest}")
    print(f"Log: {SYNTHETIC_LOG}")


if __name__ == "__main__":
    main()
