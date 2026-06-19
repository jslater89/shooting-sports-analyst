---
name: db-oneoff-generator
description: >-
  Scaffold and implement bin/db_oneoffs.dart research commands (DbOneoffCommand).
  Use when the user asks for a DB oneoff, db_oneoff, research script against
  AnalystDatabase, rating-project analysis, or a new menu command under bin/db_oneoff_impl/.
---

# DB Oneoff Generator

## When to Use

Use when adding a **research / ad-hoc database command** run via:

```bash
dart run bin/db_oneoffs.dart
```

These are **not** production UI routes. They live under `bin/db_oneoff_impl/` and plug into the interactive menu in `bin/db_oneoffs.dart`.

## Before Writing Code — Ask the User

1. **Reference rating project** — propose default **`L2s Main LLR`**. Confirm or override (e.g. `L2s Main`, `L2s Main Glicko`). Store as a named constant like `kDefaultLlrProjectName`.
2. **Menu key** — short uppercase key (2–4 chars, unique among existing commands). Check `bin/db_oneoffs.dart` `menuLoop` list.
3. **Arguments** — interactive only, or also a **CLI shortcut** in `main` (see `AMR`, `CFA` in `bin/db_oneoffs.dart`)?
4. **Match discovery** — if match names are ambiguous, use **placeholder search terms** the user will fill in (see `kNationalsSearchTerms` in `co_lo_nationals_overlap_command.dart`).
5. **Rating group(s)** — division group vs combined group (e.g. `uspsa-lo-co` uuid)? Confirm before assuming per-division ratings.
6. **Identity comparison** — when comparing shooters across matches/groups, use `ShooterRating.equalsShooter(..., allPossibleMemberNumbers: true)`, not `==` or `DbShooterRating.id`.

Skip questions the user already answered.

## Reference Files

| File | Role |
|------|------|
| [bin/db_oneoff_impl/base.dart](bin/db_oneoff_impl/base.dart) | `DbOneoffCommand` base class |
| [lib/console/repl.dart](lib/console/repl.dart) | `MenuCommand`, `MenuCommandClass`, `MenuArgument`, `menuLoop`, argument types |
| [bin/db_oneoffs.dart](bin/db_oneoffs.dart) | `main`, DB bootstrap, `menuLoop` registration, optional CLI branches |

## Implementation Checklist

```
- [ ] Create bin/db_oneoff_impl/<snake_case>_command.dart
- [ ] MPL license header (copy from sibling oneoff)
- [ ] Class extends DbOneoffCommand with key, title, description?, arguments?, executor
- [ ] Import command in bin/db_oneoffs.dart
- [ ] Add instance to menuLoop([...]) list (before QuitCommand)
- [ ] Optional: CLI branch in main if user wants non-interactive launch
- [ ] Document launch line in file header comment if CLI args exist
```

## Command Skeleton

```dart
import "package:dart_console/dart_console.dart";
import "package:shooting_sports_analyst/console/repl.dart";
import "package:shooting_sports_analyst/data/database/analyst_database.dart";
import "package:shooting_sports_analyst/data/database/match/rating_project_database.dart";
import "base.dart";

const String kDefaultLlrProjectName = "L2s Main LLR";

class ExampleResearchCommand extends DbOneoffCommand {
  ExampleResearchCommand(AnalystDatabase db) : super(db);

  @override
  final String key = "EX";

  @override
  final String title = "Example Research";

  @override
  String? get description => "One-line summary for menu help.";

  @override
  List<MenuArgument> get arguments => [
        IntMenuArgument(label: "Year", required: true),
      ];

  @override
  Future<void> executor(Console console, List<MenuArgumentValue> arguments) async {
    await _run(db, console, projectName: kDefaultLlrProjectName);
  }
}
```

Register in `bin/db_oneoffs.dart`:

```dart
import "db_oneoff_impl/example_research_command.dart";
// ...
ExampleResearchCommand(db),
```

## Common Data Patterns

### Load rating project

```dart
final project = await db.getRatingProjectByName(projectName);
if (project == null) {
  console.print("Rating project not found: $projectName");
  return;
}
if (!project.dbGroups.isLoaded) {
  await project.dbGroups.load();
}
```

### Find matches in project

Filter `project.matchPointers` by date, name substring, regex. Warn when multiple pointers match.

### Hydrate match + scores

```dart
final res = await ptr.getDbMatch(db, downloadIfMissing: false);
// load shooterLinks if shootersStoredSeparately
final shootingMatch = (await dbMatch.hydrate()).unwrap();
final scores = shootingMatch.getScoresFromFilters(group.filters);
```

Respect `matchEntry.dq` and `group.filters.reentries` when counting competitors (see `area_match_research_command.dart`).

### Map roster entry → rating

```dart
db.maybeKnownShooterSync(
  project: project,
  group: group,
  memberNumber: mn,
  usePossibleMemberNumbers: true,
);
// wrap: project.wrapDbRatingSync(dbRating)
```

### Match-time rating (pre-match)

```dart
rating.ratingForEvent(shootingMatch, null, beforeMatch: true)
```

### Combined LO/CO group

Built-in uuid: `uspsa-lo-co`. Resolve with `project.groups.firstWhereOrNull((g) => g.uuid == "uspsa-lo-co")`. Use per-division groups only for **roster filters** when needed.

## Example Commands by Pattern

| Pattern | Reference |
|---------|-----------|
| Match pointers + hydrated scores + group filters | `area_match_research_command.dart` |
| Many menu args + CLI shortcut + CSV output | `career_field_adjusted_metrics_command.dart` |
| Cross-match identity + rating tiers | `co_lo_nationals_overlap_command.dart` |
| Per-rating loops + progress bar | `open_style_analysis_command.dart` |
| Algorithm-specific (Latent Log) | `rating_demographics_by_class_command.dart` |

## Output Conventions

- Build reports with `StringBuffer`, then `console.print(buf.toString())` once.
- Include project name, filters, and identity method in the header.
- Use `_pct(numerator, denominator)` helpers for percentage lines with counts.
- For long loops over ratings/matches, use `LabeledProgressBar` from `console/labeled_progress_bar.dart`.

## Code Style (Project)

- Double-quoted strings in Dart.
- `if { } else { }` brace style (not `} else {` on one line).
- `final _log = SSALogger("Tag")` when logging; import via package path.
- **Do not run `dart format`** unless the user asks.
- Minimize scope — one focused command file; extract `_run` and private helpers in the same file unless reuse is obvious.

## CLI Shortcut (Optional)

When adding non-interactive launch, mirror `AMR` / `CFA` in `bin/db_oneoffs.dart`:

1. Parse `args` in `main` before `menuLoop`.
2. Map positional args to `MenuArgumentValue` wrappers.
3. Print usage when args are missing.
4. Document: `dart run bin/db_oneoffs.dart <KEY> [args...]`

Only add a CLI branch when the user wants repeatable runs without the menu.

## Verification

1. `dart analyze bin/db_oneoff_impl/<file>.dart` (or read lints).
2. `dart run bin/db_oneoffs.dart` — confirm new key appears in menu.
3. Run the command against local DB; confirm sensible output for missing project / no matches.

Do **not** commit unless the user asks.
