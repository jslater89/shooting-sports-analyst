/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

/// Who completed the most rated stages in a single calendar month.
///
/// Uses [L2s Main] (Elo, byStage) so each rating event is a completed
/// stage. LLR match-level `lengthInStages` would count stages on finished
/// matches, including ones the shooter did not complete.
///
/// Identity is merged across single-division groups via normalized
/// allPossibleMemberNumbers. Combined groups (e.g. LOCO) are skipped so
/// the same stage is not counted twice.
///
/// Launch: dart run bin/db_oneoffs.dart MSM [project] [topN]
/// Example: MSM "L2s Main" 25

import "package:collection/collection.dart";
import "package:dart_console/dart_console.dart";
import "package:shooting_sports_analyst/console/labeled_progress_bar.dart";
import "package:shooting_sports_analyst/console/repl.dart";
import "package:shooting_sports_analyst/data/database/analyst_database.dart";
import "package:shooting_sports_analyst/data/database/match/rating_project_database.dart";
import "package:shooting_sports_analyst/data/database/schema/ratings.dart";
import "package:shooting_sports_analyst/data/ranking/deduplication/shooter_deduplicator.dart";

import "base.dart";

const String kDefaultEloProjectName = "L2s Main";
const int kDefaultTopN = 25;
const int kWinnerMatchListCap = 20;

class MostStagesInMonthCommand extends DbOneoffCommand {
  MostStagesInMonthCommand(AnalystDatabase db) : super(db);

  @override
  final String key = "MSM";

  @override
  final String title = "Most Stages in a Month";

  @override
  String? get description =>
      "Who completed the most Elo-rated stages in a single calendar month, "
      "merged across divisions by member number.";

  @override
  List<MenuArgument> get arguments => [
        StringMenuArgument(
          label: "Project name",
          required: false,
          defaultValue: kDefaultEloProjectName,
          description: "Rating project. Elo / byStage (L2s Main) is required.",
        ),
        IntMenuArgument(
          label: "Top N",
          required: false,
          defaultValue: kDefaultTopN,
          description: "How many person-months to list.",
        ),
      ];

  @override
  Future<void> executor(Console console, List<MenuArgumentValue> arguments) async {
    final projectName = arguments
            .firstWhereOrNull((a) => a.argument.label == "Project name")
            ?.getAs<String>()
            .trim() ??
        kDefaultEloProjectName;
    final topN = arguments
            .firstWhereOrNull((a) => a.argument.label == "Top N")
            ?.getAs<int>() ??
        kDefaultTopN;
    await _run(
      db,
      console,
      projectName: projectName.isEmpty ? kDefaultEloProjectName : projectName,
      topN: topN < 1 ? kDefaultTopN : topN,
    );
  }
}

Future<void> _run(
  AnalystDatabase db,
  Console console, {
  required String projectName,
  required int topN,
}) async {
  final project = await db.getRatingProjectByName(projectName);
  if (project == null) {
    console.print("Rating project not found: $projectName");
    return;
  }
  if (!project.dbGroups.isLoaded) {
    await project.dbGroups.load();
  }

  if (!project.settings.byStage) {
    console.print(
      "Project $projectName is not byStage. Use L2s Main (Elo) so each "
      "event is a completed stage; LLR match-level lengthInStages counts "
      "stages on finished matches.",
    );
    return;
  }

  final groups = project.groups
      .where((g) => g.divisionNames.length == 1)
      .sorted((a, b) => a.sortOrder.compareTo(b.sortOrder))
      .toList();
  if (groups.isEmpty) {
    console.print("No single-division groups in $projectName.");
    return;
  }

  final matchNameById = <String, String>{};
  for (final ptr in project.matchPointers) {
    for (final id in ptr.sourceIds) {
      matchNameById[id] = ptr.name;
    }
  }

  final groupedRatings = <RatingGroup, List<DbShooterRating>>{};
  var ratingTotal = 0;
  for (final group in groups) {
    final res = project.getRatingsSync(group);
    if (res.isErr()) {
      console.print("${group.uiLabel}: failed to load ratings.");
      return;
    }
    final ratings = res.unwrap();
    groupedRatings[group] = ratings;
    ratingTotal += ratings.length;
  }

  final idIndex = _PersonIdIndex();
  for (final ratings in groupedRatings.values) {
    for (final rating in ratings) {
      idIndex.idFor(rating);
    }
  }

  final people = <int, _Person>{};
  final bar = LabeledProgressBar(
    maxValue: ratingTotal,
    initialLabel: "Counting stages by month...",
  );

  for (final entry in groupedRatings.entries) {
    final groupLabel = entry.key.uiLabel;
    for (final rating in entry.value) {
      bar.tick();
      if (rating.cachedLength <= 0) {
        continue;
      }
      final personId = idIndex.idFor(rating);
      final person = people.putIfAbsent(personId, _Person.new);
      person.observe(rating);

      final events = db.getRatingEventsForSync(rating);
      for (final event in events) {
        if (event.stageNumber < 0) {
          continue;
        }
        final month = _monthKey(event.date);
        person.stagesByMonth
            .putIfAbsent(month, () => <String>{})
            .add("${event.matchId}|${event.entryId}|${event.stageNumber}");
        person.matchesByMonth
            .putIfAbsent(month, () => <String>{})
            .add(event.matchId);
        person.divisionsByMonth
            .putIfAbsent(month, () => <String>{})
            .add(groupLabel);
      }
    }
  }
  bar.complete();

  final rows = <_MonthRow>[];
  for (final person in people.values) {
    for (final month in person.stagesByMonth.keys) {
      rows.add(_MonthRow(
        person: person,
        month: month,
        stages: person.stagesByMonth[month]!.length,
        matches: person.matchesByMonth[month]?.length ?? 0,
        divisions: (person.divisionsByMonth[month] ?? const <String>{})
            .toList()
          ..sort(),
        matchIds: person.matchesByMonth[month] ?? const <String>{},
      ));
    }
  }
  rows.sort((a, b) {
    final byStages = b.stages.compareTo(a.stages);
    if (byStages != 0) {
      return byStages;
    }
    final byMatches = b.matches.compareTo(a.matches);
    if (byMatches != 0) {
      return byMatches;
    }
    final byMonth = b.month.compareTo(a.month);
    if (byMonth != 0) {
      return byMonth;
    }
    return a.person.name.compareTo(b.person.name);
  });

  final listed = rows.take(topN).toList();
  final buf = StringBuffer()
    ..writeln("=== Most Stages in a Single Month ===")
    ..writeln("Project: $projectName")
    ..writeln("Algorithm: ${project.settings.algorithm.runtimeType}")
    ..writeln("Groups: single-division only (${groups.map((g) => g.uiLabel).join(", ")})")
    ..writeln("Identity: allPossibleMemberNumbers index (normalized)")
    ..writeln(
      "Count: Elo stage-level rating events (stageNumber >= 0), unique "
      "(matchId, entryId, stageNumber) so two-gun entries both count",
    )
    ..writeln("Month: calendar month of the match start date")
    ..writeln("People with stages: ${people.length}")
    ..writeln("Person-months: ${rows.length}")
    ..writeln("");

  if (listed.isEmpty) {
    buf.writeln("No stage events found.");
    console.print(buf.toString());
    return;
  }

  buf.writeln("--- Top $topN person-months ---");
  buf.writeln(
    "${"#".padLeft(3)}  "
    "${"Stages".padLeft(6)}  "
    "${"Mtch".padLeft(4)}  "
    "${"Month".padRight(8)}  "
    "${"Name".padRight(28)}  "
    "${"Member #".padRight(12)}  "
    "Divisions",
  );
  buf.writeln("-" * 110);
  for (var i = 0; i < listed.length; i++) {
    final row = listed[i];
    buf.writeln(
      "${"${i + 1}".padLeft(3)}  "
      "${"${row.stages}".padLeft(6)}  "
      "${"${row.matches}".padLeft(4)}  "
      "${row.month.padRight(8)}  "
      "${_fit(row.person.name, 28).padRight(28)}  "
      "${_fit(row.person.memberNumber, 12).padRight(12)}  "
      "${row.divisions.join(", ")}",
    );
  }

  final winner = listed.first;
  buf
    ..writeln("")
    ..writeln("--- Winner ---")
    ..writeln(
      "${winner.person.name} (${winner.person.memberNumber}) completed "
      "${winner.stages} stages across ${winner.matches} matches in ${winner.month} "
      "(${winner.divisions.join(", ")}).",
    );

  final winnerOther = rows
      .where((r) => identical(r.person, winner.person) && r.month != winner.month)
      .take(5)
      .toList();
  if (winnerOther.isNotEmpty) {
    buf.writeln("Other peak months for the same shooter:");
    for (final row in winnerOther) {
      buf.writeln(
        "  ${row.month}: ${row.stages} stages / ${row.matches} matches "
        "(${row.divisions.join(", ")})",
      );
    }
  }

  final matchNames = winner.matchIds
      .map((id) => matchNameById[id] ?? id)
      .toList()
    ..sort();
  buf.writeln("Matches in ${winner.month}:");
  final shown = matchNames.take(kWinnerMatchListCap).toList();
  for (final name in shown) {
    buf.writeln("  $name");
  }
  if (matchNames.length > shown.length) {
    buf.writeln("  ... and ${matchNames.length - shown.length} more");
  }

  console.print(buf.toString());
}

String _monthKey(DateTime date) {
  final month = date.month.toString().padLeft(2, "0");
  return "${date.year}-$month";
}

String _fit(String value, int width) {
  if (value.length <= width) {
    return value;
  }
  if (width <= 1) {
    return value.substring(0, width);
  }
  return "${value.substring(0, width - 1)}…";
}

class _MonthRow {
  _MonthRow({
    required this.person,
    required this.month,
    required this.stages,
    required this.matches,
    required this.divisions,
    required this.matchIds,
  });

  final _Person person;
  final String month;
  final int stages;
  final int matches;
  final List<String> divisions;
  final Set<String> matchIds;
}

class _Person {
  String name = "";
  String memberNumber = "";
  DateTime lastSeen = DateTime.fromMillisecondsSinceEpoch(0);
  final Map<String, Set<String>> stagesByMonth = {};
  final Map<String, Set<String>> matchesByMonth = {};
  final Map<String, Set<String>> divisionsByMonth = {};

  void observe(DbShooterRating rating) {
    if (rating.lastSeen.isAfter(lastSeen) || name.isEmpty) {
      lastSeen = rating.lastSeen;
      name = rating.getName(suffixes: false);
      memberNumber = rating.memberNumber;
    }
  }
}

Iterable<String> _numberKeys(DbShooterRating rating) sync* {
  final seen = <String>{};
  for (final raw in [
    rating.memberNumber,
    ...rating.knownMemberNumbers,
    ...rating.allPossibleMemberNumbers,
  ]) {
    final t = raw.trim();
    if (t.isEmpty || t == "(invalid)") {
      continue;
    }
    final key = ShooterDeduplicator.normalizeNumberBasic(t);
    if (key.isEmpty || !seen.add(key)) {
      continue;
    }
    yield key;
  }
}

/// Stable person IDs across division rows via shared number keys.
class _PersonIdIndex {
  final Map<String, int> _keyToId = {};
  final Map<int, int> _redirect = {};
  var _nextId = 0;

  int _root(int id) {
    var cur = id;
    while (_redirect.containsKey(cur)) {
      cur = _redirect[cur]!;
    }
    return cur;
  }

  int idFor(DbShooterRating rating) {
    final keys = _numberKeys(rating).toList();
    if (keys.isEmpty) {
      return _nextId++;
    }

    final found = <int>{};
    for (final k in keys) {
      final existing = _keyToId[k];
      if (existing != null) {
        found.add(_root(existing));
      }
    }

    late final int id;
    if (found.isEmpty) {
      id = _nextId++;
    }
    else {
      id = found.first;
      for (final other in found.skip(1)) {
        if (other != id) {
          _redirect[other] = id;
        }
      }
    }

    for (final k in keys) {
      _keyToId[k] = id;
    }
    return id;
  }
}
