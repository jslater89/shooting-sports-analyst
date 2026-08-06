/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

/// Smoke-test the research facade (direct DB). Usage:
///   dart run bin/mcp/ssa_research_smoke.dart [match query]
import "dart:io";

import "package:shooting_sports_analyst/config/serialized_config.dart";
import "package:shooting_sports_analyst/data/database/analyst_database.dart";
import "package:shooting_sports_analyst/flutter_native_providers.dart";
import "package:shooting_sports_analyst/logger.dart";
import "package:shooting_sports_analyst/research/research_facade.dart";
import "package:shooting_sports_analyst/server/providers.dart";

Future<void> main(List<String> args) async {
  FlutterOrNative.debugModeProvider = ServerDebugProvider();
  FlutterOrNative.isolateModeProvider = ServerDebugProvider(isMultiIsolate: false);
  SSALogger.consoleOutput = true;
  SSALogger.fileOutput = false;
  await ConfigLoader().readyFuture;

  final db = AnalystDatabase();
  await db.ready;
  final facade = ResearchFacade(db);

  final projects = await facade.listRatingProjects(limit: 5);
  stdout.writeln("Projects (${projects.length}):");
  for (final p in projects) {
    stdout.writeln("  - ${p.name} (${p.matchCount} matches, ${p.groups.length} groups)");
  }

  final query = args.isNotEmpty ? args.join(" ") : "Area 5 Championship";
  final matches = await facade.searchMatches(query: query, limit: 5);
  stdout.writeln("\nMatches for '$query':");
  for (final m in matches) {
    stdout.writeln("  - ${m.id}: ${m.name} (${m.date.toIso8601String().split("T").first})");
  }

  if (matches.isNotEmpty) {
    final winners = await facade.getMatchWinners(matchId: matches.first.id, topN: 1);
    stdout.writeln("\nWinners for ${winners.match.name}:");
    for (final w in winners.winners.where((w) => w.place == 1).take(12)) {
      stdout.writeln(
        "  ${w.divisionOrGroup}: ${w.name} (${w.memberNumber}) "
        "${w.percentage.toStringAsFixed(1)}% n=${w.competitorCount} "
        "F=${w.female} age=${w.ageCategory} cats=${w.categories}",
      );
    }

    final results = await facade.getMatchResults(
      matchId: matches.first.id,
      division: "Carry Optics",
      topN: 5,
    );
    stdout.writeln("\nTop ${results.results.length} of ${results.competitorCount} in ${results.pool}:");
    for (final row in results.results) {
      stdout.writeln(
        "  #${row.place} ${row.name} ${row.percentage.toStringAsFixed(1)}% "
        "F=${row.female} age=${row.ageCategory} cats=${row.categories}",
      );
    }
  }

  stdout.writeln("\nSmoke OK");
  exit(0);
}
