/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

// TODO: restore when I can do test data again

// import 'package:shooting_sports_analyst/data/ranking/raters/openskill/openskill_rater.dart';
// import 'package:shooting_sports_analyst/data/ranking/raters/openskill/openskill_rating.dart';
// import 'package:shooting_sports_analyst/data/sport/builtins/uspsa.dart';
// import 'package:shooting_sports_analyst/data/sport/model.dart';
//
// import 'openskill_settings.dart';

// class OpenskillTest {
//   static void run() {
//
//     Shooter austen = Shooter();
//     austen.firstName = "Austen";
//     austen.lastName = "Leffler";
//     austen.memberNumber = "12345";
//
//     Shooter william = Shooter();
//     austen.firstName = "William";
//     austen.lastName = "Tracy";
//     austen.memberNumber = "54321";
//
//     List<OpenskillRating> ratings = [
//       OpenskillRating(austen, OpenskillSettings.defaultMu, OpenskillSettings.defaultSigma, sport: uspsaSport),
//       OpenskillRating(william, OpenskillSettings.defaultMu, OpenskillSettings.defaultSigma, sport: uspsaSport),
//     ];
//
//     var scores = {
//       ratings[0]: RelativeScore()
//         ..relativePoints = 485
//         ..score = (Score(shooter: austen)..a=5..time=5),
//       ratings[1]: RelativeScore()
//         ..relativePoints = 187.93
//         ..score = (Score(shooter: william)..a=5..time=5)
//     };
//
//     var rater = OpenskillRater(settings: OpenskillSettings());
//     var changes = rater.updateShooterRatings(match: ShootingMatch(), shooters: ratings, scores: scores, matchScores: scores.map(
//         (k, v) => MapEntry(k, RelativeMatchScore(shooter: v.score.shooter)..total = v)
//     ));
//
//     print(changes);
//     print("expected: mu +/-2.635, sigma -0.2284");
//   }
// }