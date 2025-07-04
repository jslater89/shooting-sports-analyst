/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */


import 'package:collection/collection.dart';
import 'package:shooting_sports_analyst/data/model.dart';

class RelativeMatchScore {
  RelativeMatchScore({required this.shooter});

  Shooter shooter;
  late RelativeScore total;

  /// Percent of match max points shot
  late double percentTotalPoints;

  double percentTotalPointsWithSettings({bool scoreDQ = true, bool countPenalties = true, Map<Stage, int> stageMaxPoints = const {}}) {
    if(scoreDQ && countPenalties && stageMaxPoints.isEmpty) {
      return percentTotalPoints;
    }

    var max = maxPoints(stageMaxPoints: stageMaxPoints);
    var actualPoints = stageScores.values.map((e) => e.score.getTotalPoints(scoreDQ: scoreDQ, countPenalties: countPenalties)).sum.toDouble();

    return actualPoints / max;
  }

  int maxPoints({Map<Stage, int> stageMaxPoints = const{}}) {
    int max = 0;
    for(var stage in stageScores.keys) {
      max += stageMaxPoints[stage] ?? stageScores[stage]!.stage!.maxPoints;
    }
    return max;
  }

  /// It's safe/correct to cache DNFs, because (a) they're only used in ratings,
  /// and (b) we never edit scores belonging to ratings.
  bool? _isDnf;

  /// If a shooter has two or more DNF stages, they're assumed to have DNFed
  /// the match.
  bool get isDnf {
    if(_isDnf != null) return _isDnf!;

    int dnfs = 0;

    for(var entry in stageScores.entries) {
      if(entry.key.type != Scoring.chrono && entry.value.score.isDnf) {
        dnfs += 1;
      }

      if(dnfs >= 2) {
        _isDnf = true;
        return true;
      }
    }

    _isDnf = false;
    return false;
  }

  Map<Stage, RelativeScore> stageScores = {};
}

extension MatchScoresToCSV on List<RelativeMatchScore> {
  String toCSV() {
    String csv = "Member#,Name,MatchPoints,Percentage\n";
    var sorted = this.sorted((a, b) => a.total.place.compareTo(b.total.place));

    for(var score in sorted) {
      csv += "${score.shooter.memberNumber},";
      csv += "${score.shooter.getName(suffixes: false)},";
      csv += "${score.total.relativePoints.toStringAsFixed(2)},";
      csv += "${(score.total.percent * 100).toStringAsFixed(2)}\n";
    }

    return csv;
  }
}

class RelativeScore {
  RelativeScore();
  late Score score;

  int place = -1;

  /// If null, treat this as a match score
  Stage? stage;

  /// For stage scores, calculate this off of
  /// hit factors and use to set relative points.
  double percent = 0;

  /// For match scores, total from stage scores
  /// and use to set percent.
  double relativePoints = 0;
}
