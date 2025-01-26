/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */


import 'dart:io';

import 'package:collection/collection.dart';
import 'package:isar/isar.dart';
import 'package:shooting_sports_analyst/data/database/match/match_database.dart';
import 'package:shooting_sports_analyst/data/match/practical_match.dart';
import 'package:shooting_sports_analyst/data/match_cache/match_cache.dart';
import 'package:shooting_sports_analyst/data/ranking/project_manager.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/util.dart';
import 'package:intl/intl.dart';

SSALogger _log = SSALogger("DbOneoffs");

Future<void> oneoffDbAnalyses(AnalystDatabase db) async {
  _log.d("Starting oneoffDbAnalyses");
  // await _matchChronoCounts();
}

Future<void> _matchChronoCounts() async {
  await MatchCache().ready;
  Map<MatchLevel, List<PracticalMatch>> matches = {};
  Map<MatchLevel, int> matchCounts = {};
  Map<MatchLevel, int> chronoCounts = {};
  await RatingProjectManager().ready;

  var project = RatingProjectManager().loadProject("L2s Main");
  for(var url in project!.matchUrls) {
    var match = await MatchCache().getMatchImmediate(url);
    matches.addToList(match!.level ?? MatchLevel.I, match);
  }

  for(var match in matches.values.flattened) {
    var date = match.date!;
    if(match.name!.toLowerCase().contains("national")) {
      match.level = MatchLevel.III;
    }
    else if(match.level == MatchLevel.I || match.level == null) {
      match.level = MatchLevel.II;
    }
    matchCounts.increment(match.level ?? MatchLevel.I);
    if(match.hasChrono) {
      chronoCounts.increment(match.level ?? MatchLevel.I);
    }
  }

  for(var level in MatchLevel.values) {
    if(matchCounts[level] == null || matchCounts[level] == 0) continue;
    _log.i("Level ${level.name}: ${chronoCounts[level]}/${matchCounts[level]}");
  }

  File f = File("chrono_by_match.csv");
  String csv = "Match Name,Match Date,Probable Match Level,Has Chrono\n";
  for(var level in MatchLevel.values) {
    if(matches[level] == null || matches[level]!.isEmpty) continue;
    for(var match in matches[level]!) {
      csv += '"${match.name}",${programmerYmdFormat.format(match.date!)},${match.level?.name ?? MatchLevel.I.name},${match.hasChrono}\n';
    }
  }
  f.writeAsStringSync(csv);
  _log.i("Analysis complete: wrote ${f.path}");
}

// Future<void> _lady90PercentFinishes(AnalystDatabase db) async {
//   var startTime = DateTime.now();
//   var matches = await db.matchDb.dbShootingMatchs
//     .filter()
//     .shootersElement((q) =>
//       q.femaleEqualTo(true)
//       .and()
//       .precalculatedScore((q) => q.percentageGreaterThan(90, include: true))
//     )
//     .sortByDate()
//     .findAll();

//   var buf = StringBuffer();
//   for(var match in matches) {
//     for(var shooter in match.shooters) {
//       if(shooter.female && (shooter.precalculatedScore?.percentage ?? 0) >= 90) {
//         var competitorCount = match.shooters.where((e) => e.divisionName == shooter.divisionName).length;
//         buf.writeln('${match.date},${match.eventName.replaceAll(',', ' ')},${match.matchLevelName},${shooter.firstName},${shooter.lastName},${shooter.divisionName},${shooter.precalculatedScore?.percentage},${shooter.precalculatedScore?.place},${competitorCount}');
//       }
//     }
//   }

//   File f = File("female_90_percent.csv");
//   f.writeAsString(buf.toString());
//   _log.i("Analysis complete: wrote ${f.path} in ${DateTime.now().difference(startTime).inMilliseconds}ms");
// }