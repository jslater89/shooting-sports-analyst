/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/ranking/model/rating_change.dart';
import 'package:uspsa_result_viewer/data/ranking/model/rating_system.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/elo/multiplayer_percent_elo_rater.dart';

class EloRatingEvent extends RatingEvent {
  double ratingChange;
  final double oldRating;

  double baseK;
  double effectiveK;

  double error;
  double backRatingError;

  RelativeScore get matchScore {
    return extraData[MultiplayerPercentEloRater.matchScoreKey]! as RelativeScore;
  }

  EloRatingEvent({
    required this.oldRating,
    required PracticalMatch match,
    Stage? stage,
    required RelativeScore score,
    Map<String, List<dynamic>> info = const {},
    required this.ratingChange,
    this.error = 0,
    required this.baseK,
    required this.effectiveK,
    required this.backRatingError,
  }) : super(match: match, stage: stage, score: score, info: info);

  EloRatingEvent.copy(EloRatingEvent other) :
      this.error = other.error,
      this.oldRating = other.oldRating,
      this.ratingChange = other.ratingChange,
      this.baseK = other.baseK,
      this.effectiveK = other.effectiveK,
      this.backRatingError = other.backRatingError,
      super.copy(other);

  @override
  void apply(RatingChange change) {
    ratingChange += change.change[RatingSystem.ratingKey]!;
    error = change.change[MultiplayerPercentEloRater.errorKey]!;
    baseK = change.change[MultiplayerPercentEloRater.baseKKey]!;
    effectiveK = change.change[MultiplayerPercentEloRater.effectiveKKey]!;
    if(MultiplayerPercentEloRater.doBackRating) backRatingError = change.change[MultiplayerPercentEloRater.backRatingErrorKey]!;
    extraData = change.extraData;
  }
}