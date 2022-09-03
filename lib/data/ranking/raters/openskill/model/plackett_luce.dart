import 'dart:math';

import 'package:uspsa_result_viewer/data/ranking/model/rating_change.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/openskill/model/model_utils.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/openskill/openskill_rater.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/openskill/openskill_rating.dart';

class PlackettLuce {
  void update(OpenskillRater rater, List<OpenskillScore> teams, Map<OpenskillRating, RatingChange> changes) {
    final epsilon = rater.epsilon;
    ModelUtils.fillRankings(teams);
    final c = ModelUtils.c(rater, teams);
    ModelUtils.fillSumQ(rater, teams, c);
    ModelUtils.fillA(rater, teams);

    for(int i = 0; i < teams.length; i++) {
      final iTeam = teams[i];
      final iMuOverCe = exp(iTeam.mu / c);

      final omegaDeltaSum = teams
        .where((qTeam) => qTeam.rank <= iTeam.rank)
        .map<_OmegaDelta>((qTeam) {
          final quotient = iMuOverCe / qTeam.sumQ;
          return _OmegaDelta(
              (iTeam == qTeam ? 1 - quotient : -quotient) / qTeam.a,
              (quotient * (1 - quotient)) / qTeam.a
          );
        })
        .reduce((value, element) => _OmegaDelta(
          value.omega + element.omega, value.delta + element.delta)
        );

      // TODO: configuration?
      final iGamma = sqrt(iTeam.sigmaSquared) / c;
      final iOmega = omegaDeltaSum.omega * (iTeam.sigmaSquared / c);
      final iDelta = iGamma * omegaDeltaSum.delta * (iTeam.sigmaSquared / pow(c, 2));

      final newSigma = iTeam.sigma * sqrt(max(epsilon, 1 - iDelta));

      changes[iTeam.rating] = RatingChange(change: {
        OpenskillRater.muKey: iOmega,
        OpenskillRater.sigmaKey: newSigma - iTeam.sigma,
      });
    }
  }
}

class _OmegaDelta {
  double omega = 0.0;
  double delta = 0.0;

  _OmegaDelta(this.omega, this.delta);
}