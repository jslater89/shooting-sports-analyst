---
name: match-member-number-backfill
description: >-
  Backfill USPSA member numbers onto stored matches that only have Practiscore
  bibs or nicknames. Use when the user wants member numbers added to match
  copies, MIFF exports for a named match, a review CSV of competitor names,
  synthetic F10000xx numbers, or reimport of updated MIFFs over Practiscore
  matches. Worked example: USA Extreme Open 2024-2026.
---

# Match Member Number Backfill

Attach real or synthetic member numbers to matches whose source data has bibs, nicknames, or blanks. Keep the Practiscore match source ids so a later file import overwrites the existing row.

Pause after the review CSV. Do not write updated MIFFs until the user finishes editing it. Do not import unless asked.

Worked example, adapt rather than rerun blindly:

- Lookup: `bin/extreme_open_member_lookup.dart`
- Apply: `research/usa-extreme-open/apply_member_numbers.py`
- Outputs: `research/usa-extreme-open/`

## Output layout

Under `research/<slug>/`:

| File | Role |
|---|---|
| `miff/*.miff.gz` | Original export. Do not overwrite. |
| `member-number-review.csv` | Human review. Unresolved rows first. |
| `member-number-lookup.json` | Machine copy of the lookup, before edits. |
| `miff-with-members/*.miff.gz` | Same files with member numbers applied. |
| `synthetic-member-numbers.csv` | One row per new `F10000xx` name. |

## 1. Export

Export each named match as MIFF from the database copy. Preserve `source.code` and `source.ids` (Practiscore UUID, plus any `report-uspsa:` id). Preserve shooter `sourceId` when present.

Confirm the match list with `search_matches` on the ssa-research MCP server if names are ambiguous. Default rating project is **L2s Main LLR**.

## 2. Name lookup

Look up each competitor in L2s Main LLR with the exact deduplicator name (`FindShooterSearchMode.exact`), the same query `search_shooters` uses. Hundreds of MCP calls are unnecessary; run the lookup in-process and spot-check a few names on the MCP server.

Map each entered division to **one** USPSA rating group. IPSC matches use [lib/data/sport/builtins/links/ipsc_to_uspsa_link.dart](lib/data/sport/builtins/links/ipsc_to_uspsa_link.dart): Standard to Limited, Production Optics to Carry Optics, Optics to Limited Optics, Classic to Single Stack, PCC Optic to PCC. USPSA divisions map to themselves. A division with no link (PCC Iron) is not treated as PCC; search every group.

Ratings that share `allPossibleMemberNumbers` are one person. `A` / `TY` / `FY` and `F` / `TYF` / `FYF` forms of the same digits are one person.

A row is **resolved** when any of these is true:

- The mapped group has exactly one person with that exact name (`unique`).
- Exactly one person with that exact name exists in any other group (`other-division`).
- The match already has a USPSA-shaped member number (`existing-uspsa`). Use that entered number. If the name lookup points at a different number, put the disagreement in `note`.

USPSA-shaped means `A`/`TY`/`FY` or `F`/`TYF`/`FYF` plus 4–6 digits, `L` plus 3–4 digits, `B` plus 2–3 digits, or `RD1`–`RD25`.

Still unresolved, and sorted first: `missing`, `ambiguous`, `swapped-name` (first and last reversed), `dropped-middle` (first and last matched after dropping middle tokens). Two or more distinct people is `ambiguous` even when one of them is outside the mapped group.

CSV columns: `status`, `match`, `division`, `name`, `existingMemberNumber`, `memberNumber`, `memberNumber2`…, `alsoKnown`, `foundIn`, `candidates`, `note`, `entryId`, `sourceId`. Extra `memberNumber` columns are other people. `alsoKnown` is alternate forms of the same person.

## 3. Pause for review

Tell the user the status counts and the ambiguous rows. Stop.

After they edit the CSV, `memberNumber` is the assignment for that row:

- Any other non-empty value is written onto that entry. Fill a real number on **every year**; a value on one row is not copied to a blank row for the same name.
- `IGNORE` leaves the match entry's current number alone.
- `INC` or blank allocates the next synthetic, one per normalized name (`ShooterDeduplicator.processNameString`) across every blank/`INC` row. A filled row and a blank row for the same display name become two identities.

Prefix variants across years (`TY89979` vs `TYF89979`) are acceptable. Two different numeric cores for one nickname are acceptable when the user says deduplication will merge them. Do not silently change an automatic pick the user left in place.

Do not add these people to `invalid-foreign-shooters.txt`. That file is a worksheet for rating-time corrections when the match still stores a junk number. Editing the match replaces that step.

## 4. Write updated MIFFs

Next synthetic is one past the highest `F10000xx` already used. Check `invalid-foreign-shooters.txt`, any `synthetic-member-numbers.csv`, and what the user says. Extreme Open consumed through **F1000320**. The 2026 US IPSC Nationals run consumed through **F1000339**.

On each shooter that is not `IGNORE`:

- Set `memberNumber` to the assigned value, normalized (uppercase, alphanumeric only).
- Set `knownMemberNumbers` to that number alone. Do not keep Practiscore bibs, `FR`, `FOREIGN`, or other shared tokens.
- Omit `originalMemberNumber` when it would be the old bib.

Leave match source ids, shooter source ids, and scores unchanged. Report the highest synthetic number used.

Reimport is a separate step. The match file import dialog calls `saveMatch`, which finds the existing row by any source id and replaces it. Auto-import skips a file whose source ids already exist unless `autoImportOverwrites` is on. Ratings stay stale until a recalc.
