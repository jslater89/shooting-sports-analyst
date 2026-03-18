---
name: generated-code-guard
description: Prevent edits to generated files (Isar/BuildRunner outputs) and ensure the source schema/model is updated instead. Use when the proposed change touches *.g.dart, part "...g.dart", or other build outputs.
---

# Generated Code Guard

## When to Use
Use this skill when:
- An edit request targets `*.g.dart`
- Or the change involves a Dart file that has `part '...g.dart';`
- Or the agent is tempted to "just patch" generated outputs

## Instructions
1. Stop: never directly modify `*.g.dart` or other build outputs.
2. Locate the owning source file:
   - Find the `part '...g.dart'` directive and treat the file as generated-API surface.
   - Edit the corresponding source schema/entity/model file under `lib/data/**` instead.
3. Re-run regeneration later (do not do it blindly inside the edit):
   - Plan to regenerate the outputs via the repo’s normal build process (e.g. `build_runner` or the project’s build script).
4. Ensure compile-time wiring is consistent:
   - If you changed an `@collection` schema class, confirm it is still registered in `AnalystDatabase`’s `Isar.open([...])` list.
5. Validate:
   - After regeneration, ensure `flutter analyze` (or `dart analyze`) is clean.

## Non-goals
This skill does not run generation commands automatically unless the user explicitly requests it.
