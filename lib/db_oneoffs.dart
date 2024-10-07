/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */


import 'dart:io';

import 'package:isar/isar.dart';
import 'package:shooting_sports_analyst/data/database/match_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/match.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/logger.dart';

SSALogger _log = SSALogger("DbOneoffs");

Future<void> oneoffDbAnalyses(AnalystDatabase db) async {

}

Future<void> _lady90PercentFinishes(AnalystDatabase db) async {
  var startTime = DateTime.now();
  var matches = await db.matchDb.dbShootingMatchs
    .filter()
    .shootersElement((q) =>
      q.femaleEqualTo(true)
      .and()
      .precalculatedScore((q) => q.percentageGreaterThan(90, include: true))
    )
    .sortByDate()
    .findAll();

  var buf = StringBuffer();
  for(var match in matches) {
    for(var shooter in match.shooters) {
      if(shooter.female && (shooter.precalculatedScore?.percentage ?? 0) >= 90) {
        var competitorCount = match.shooters.where((e) => e.divisionName == shooter.divisionName).length;
        buf.writeln('${match.date},${match.eventName.replaceAll(',', ' ')},${match.matchLevelName},${shooter.firstName},${shooter.lastName},${shooter.divisionName},${shooter.precalculatedScore?.percentage},${shooter.precalculatedScore?.place},${competitorCount}');
      }
    }
  }

  File f = File("female_90_percent.csv");
  f.writeAsString(buf.toString());
  _log.i("Analysis complete: wrote ${f.path} in ${DateTime.now().difference(startTime).inMilliseconds}ms");
}