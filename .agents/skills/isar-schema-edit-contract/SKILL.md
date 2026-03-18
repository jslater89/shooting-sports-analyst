---
name: isar-schema-edit-contract
description: Enforce the multi-file edit contract for Isar schema changes (schema class + Isar registration + migrations + link/backlink + hydration assumptions). Use when editing any `@collection` entity under `lib/data/database/schema/**`.
---

# Isar Schema Edit Contract

## When to Use
Use this skill when:
- The agent edits an Isar schema/entity class (a Dart file containing `@collection`)
- The agent is adding/removing persistent fields, links, indices, or equality/ID logic for an Isar entity

## Edit Contract (what “done” means)
The schema change is complete only when all of the following are satisfied:
1. **Isar registration**
   - Verify the schema type is included in `lib/data/database/analyst_database.dart` inside `Isar.open([...])`.
2. **Migrations**
   - If the persistent shape changes (field/link/index changes), ensure a migration is implemented in `lib/data/database/migrations/**` (or the project’s migration mechanism).
3. **Backlinks and links**
   - Ensure any `@Backlink` / `IsarLink` / `IsarLinks` relationships still line up with the IDs and collection names used elsewhere.
4. **Dehydrate/hydrate boundaries**
   - If conversion helpers exist (e.g., `fromHydrated(...)`, `hydrate()`, `asShooter(...)`), update them to reflect new field semantics and nullability.
5. **Query/extension consumers**
   - Update any DB extension methods under `lib/data/database/extensions/**` that query, sort, or filter by schema fields.
6. **Identity / equality**
   - If IDs or equality depend on fields you changed, verify all hash/equality usage and any caches keyed by those identities.

## Quick Validation Checklist
- Build/regenerate generated code if applicable
- Ensure compilation succeeds
- Ensure relevant UI paths still load/save the entity correctly
