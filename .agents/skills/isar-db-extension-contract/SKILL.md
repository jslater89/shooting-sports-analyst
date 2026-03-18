---
name: isar-db-extension-contract
description: Maintain query semantics and sorting/grouping invariants when editing DB extension methods under `lib/data/database/extensions/**`. Use when the agent changes filters, indexes, ordering, or which entity rows are selected.
---

# Isar DB Extension Contract

## When to Use
Use this skill when editing any file under:
- `lib/data/database/extensions/**`

## Why it matters
UI layers frequently assume that DB extension functions return results in a stable order
and with consistent filtering semantics.

## Instructions
1. **Capture invariants**
   - Determine which properties downstream code expects in a specific order (e.g. group/member/type/timestamp).
2. **Update both async and sync variants**
   - If the extension provides both `foo()` and `fooSync()`, keep their behavior aligned.
3. **Preserve filter meaning**
   - If the extension relies on calls like `lastBetTimestampGreaterThan(..., include: true)` or compatibility-type selection, preserve their meaning.
4. **Index alignment**
   - Ensure any referenced index/property names match the schema entity fields they query.
5. **Cache invalidation**
   - If the extension clears cached rows on config changes (e.g., `configHash` mismatch), preserve the invalidation trigger logic.

## Quick Verification Checklist
- Compile succeeds
- The UI list/detail screen using this extension still shows correct ordering and expected elements
