/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

/// Per-division match heat for USPSA Nationals in one year.
///
/// Uses the same Nationals name filter as Nationals Points vs Champion.
/// Ratings and weights come from [MatchHeatDatabase.calculateHeatCalculation],
/// so the table is the calculation the heat graph stores, plus the division
/// rows that calculation otherwise drops.
///
/// Launch: dart run bin/db_oneoffs.dart MHD [year] [project]
/// Example: dart run bin/db_oneoffs.dart MHD 2026 "L2s Main LLR"

import "package:collection/collection.dart";
import "package:dart_console/dart_console.dart";
import "package:shooting_sports_analyst/console/labeled_progress_bar.dart";
import "package:shooting_sports_analyst/console/repl.dart";
import "package:shooting_sports_analyst/data/database/analyst_database.dart";
import "package:shooting_sports_analyst/data/database/extensions/match_heat.dart";
import "package:shooting_sports_analyst/data/database/match/rating_project_database.dart";

import "base.dart";

const String kDefaultLlrProjectName = "L2s Main LLR";
const int kDefaultYear = 2026;

/// Whole-word Nationals, or "National Championship(s)".
final RegExp kNationalsNamePattern = RegExp(
  r"\bNationals\b|\bNational\s+Championships?\b",
  caseSensitive: false,
);

/// Same exclusions as Distinguished Grandmaster, plus multigun nationals.
final RegExp kNationalsExcludePattern = RegExp(
  r"\bIPSC\b|Shooting International|\bmultigun\b|\bmulti-gun\b|\b3-gun\b|\b3gun\b",
  caseSensitive: false,
);

bool _isUspsaNationalsName(String name) {
  return kNationalsNamePattern.hasMatch(name) && !kNationalsExcludePattern.hasMatch(name);
}

class MatchHeatDebugCommand extends DbOneoffCommand {
  MatchHeatDebugCommand(AnalystDatabase db) : super(db);

  @override
  final String key = "MHD";

  @override
  final String title = "Match Heat by Division";

  @override
  String? get description =>
      "Division weights and contributions for USPSA Nationals match heat. "
      "Defaults to 2026 in L2s Main LLR.";

  @override
  List<MenuArgument> get arguments => [
        IntMenuArgument(
          label: "Year",
          required: false,
          defaultValue: kDefaultYear,
          description: "Calendar year of the Nationals matches.",
        ),
        StringMenuArgument(
          label: "Project name",
          required: false,
          defaultValue: kDefaultLlrProjectName,
          description: "Rating project whose division groups supply the ratings.",
        ),
      ];

  @override
  Future<void> executor(Console console, List<MenuArgumentValue> arguments) async {
    final year = arguments
            .firstWhereOrNull((a) => a.argument.label == "Year")
            ?.getAs<int>() ??
        kDefaultYear;
    final projectName = arguments
            .firstWhereOrNull((a) => a.argument.label == "Project name")
            ?.getAs<String>()
            .trim() ??
        kDefaultLlrProjectName;
    await _run(
      db,
      console,
      year: year,
      projectName: projectName.isEmpty ? kDefaultLlrProjectName : projectName,
    );
  }
}

Future<void> _run(
  AnalystDatabase db,
  Console console, {
  required int year,
  required String projectName,
}) async {
  final project = await db.getRatingProjectByName(projectName);
  if (project == null) {
    console.print("Rating project not found: $projectName");
    return;
  }
  if (!project.dbGroups.isLoaded) {
    await project.dbGroups.load();
  }

  final pointers = project.matchPointers
      .where((p) => p.sportName.toLowerCase() == "uspsa")
      .where((p) => p.date?.year == year)
      .where((p) => _isUspsaNationalsName(p.name))
      .toList()
    ..sort((a, b) => (a.date ?? DateTime(1970)).compareTo(b.date ?? DateTime(1970)));

  if (pointers.isEmpty) {
    final nearby = project.matchPointers
        .where((p) => p.sportName.toLowerCase() == "uspsa")
        .where((p) => p.date?.year == year)
        .where((p) => p.name.toLowerCase().contains("national"))
        .map((p) => p.name)
        .toList();
    console.print("No USPSA Nationals matches in $year for $projectName.");
    if (nearby.isNotEmpty) {
      console.print("Names containing \"national\" that did not pass the filter:");
      for (final name in nearby) {
        console.print("  $name");
      }
    }
    return;
  }

  final buf = StringBuffer();
  buf.writeln("Match heat by division");
  buf.writeln("Project: $projectName");
  buf.writeln("Year: $year");
  buf.writeln("Matches: ${pointers.length}");

  final bar = LabeledProgressBar(
    maxValue: pointers.length,
    canHaveErrors: true,
    initialLabel: "Calculating Nationals heat…",
  );

  for (final ptr in pointers) {
    final calculation = await db.calculateHeatCalculation(project.id, ptr);
    buf.writeln();
    buf.writeln(calculation.describe());
    bar.tick(ptr.name);
  }

  bar.complete();
  console.print(buf.toString());
}
