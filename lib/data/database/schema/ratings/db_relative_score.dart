/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:isar/isar.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/scoring.dart';

part 'db_relative_score.g.dart';

@embedded
class DbRelativeScore {
  /// The ordinal place represented by this score: 1 for 1st, 2 for 2nd, etc.
  int place;
  /// The ratio of this score to the winning score: 1.0 for the winner, 0.9 for a 90% finish,
  /// 0.8 for an 80% finish, etc.
  double ratio;
  @ignore
  /// A convenience getter for [ratio] * 100.
  double get percentage => ratio * 100;

  /// points holds the final score for this relative score, whether
  /// calculated or simply repeated from an attached [RawScore].
  ///
  /// In a [RelativeStageFinishScoring] match, it's the number of stage
  /// points or the total number of match points. In a [CumulativeScoring]
  /// match, it's the final points or time per stage/match.
  double points;

  /// The margin in points between this score and the winning score.
  double? pointsMargin;
  /// The margin in ratio between this score and the winning score.
  double? ratioMargin;

  @ignore
  /// The margin in percentage between this score and the winning score.
  double? get percentageMargin => ratioMargin != null ? ratioMargin! * 100 : null;

  DbRelativeScore({
    this.place = 0,
    this.ratio = 0,
    this.points = 0,
    this.pointsMargin,
    this.ratioMargin,
  });

  DbRelativeScore.fromHydrated(RelativeScore score) :
      place = score.place,
      ratio = score.ratio,
      points = score.points,
      pointsMargin = score.pointsMargin,
      ratioMargin = score.ratioMargin;

  DbRelativeScore copy() {
    return DbRelativeScore(
      place: place,
      ratio: ratio,
      points: points,
      pointsMargin: pointsMargin,
      ratioMargin: ratioMargin,
    );
  }
}
