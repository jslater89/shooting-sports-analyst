import 'package:uspsa_result_viewer/data/match/shooter.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/openskill/openskill_rater.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/openskill/openskill_rating.dart';

import 'openskill_settings.dart';

class OpenskillTest {
  static void run() {

    Shooter austen = Shooter();
    austen.firstName = "Austen";
    austen.lastName = "Leffler";
    austen.memberNumber = "12345";

    Shooter william = Shooter();
    austen.firstName = "William";
    austen.lastName = "Tracy";
    austen.memberNumber = "54321";

    List<OpenskillRating> ratings = [
      OpenskillRating(austen, OpenskillSettings.defaultMu, OpenskillSettings.defaultSigma),
      OpenskillRating(william, OpenskillSettings.defaultMu, OpenskillSettings.defaultSigma),
    ];

    var scores = {
      ratings[0]: RelativeScore()
        ..relativePoints = 485
        ..score = (Score(shooter: austen)..a=5..time=5),
      ratings[1]: RelativeScore()
        ..relativePoints = 187.93
        ..score = (Score(shooter: william)..a=5..time=5)
    };

    var rater = OpenskillRater(settings: OpenskillSettings());
    var changes = rater.updateShooterRatings(match: PracticalMatch(), shooters: ratings, scores: scores, matchScores: scores);

    print(changes);
    print("expected: mu +/-2.635, sigma -0.2284");
  }
}