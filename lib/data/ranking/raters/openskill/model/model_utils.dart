import 'dart:math';

import 'package:collection/collection.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/openskill/openskill_rater.dart';

class ModelUtils {
  static void fillRankings(List<OpenskillScore> teams) {
    var s = 0;
    for (var j = 0; j < teams.length; j += 1) {
      if (j > 0 && teams[j - 1].score < teams[j].score) {
        s = j;
      }
      teams[j].rank = s;
    }
  }

  static double c(OpenskillRater rater, List<OpenskillScore> teams) {
    return sqrt(
      teams.map((t) => t.sigmaSquared + rater.betaSquared).sum
    );
  }

  static fillSumQ(OpenskillRater rater, List<OpenskillScore> teams, double c) {
    for(var q in teams) {
      q.sumQ = teams
          .where((i) => i.rank >= q.rank)
          .map((i) => exp(i.mu / c))
          .sum;
    }
  }

  static fillA(OpenskillRater rater, List<OpenskillScore> teams) {
    for(var i in teams) {
      i.a = teams
          .where((q) => q.rank == i.rank)
          .length;
    }
  }
}