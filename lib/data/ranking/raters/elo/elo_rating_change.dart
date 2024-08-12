/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/data/database/schema/match.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_change.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_system.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/elo/multiplayer_percent_elo_rater.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/scoring.dart';

import '../../../database/schema/ratings.dart';

enum _DoubleKeys {
  error,
  baseK,
  effectiveK,
  backRatingError,
}

class EloRatingEvent extends RatingEvent {
  // RelativeScore get matchScore {
  //   return extraData[MultiplayerPercentEloRater.matchScoreKey]! as RelativeScore;
  // }

  double get error => wrappedEvent.doubleData[_DoubleKeys.error.index];
  set error(double v) => wrappedEvent.doubleData[_DoubleKeys.error.index] = v;

  double get baseK => wrappedEvent.doubleData[_DoubleKeys.baseK.index];
  set baseK(double v) => wrappedEvent.doubleData[_DoubleKeys.baseK.index] = v;

  double get effectiveK => wrappedEvent.doubleData[_DoubleKeys.effectiveK.index];
  set effectiveK(double v) => wrappedEvent.doubleData[_DoubleKeys.effectiveK.index] = v;

  double get backRatingError => wrappedEvent.doubleData[_DoubleKeys.backRatingError.index];
  set backRatingError(double v) => wrappedEvent.doubleData[_DoubleKeys.backRatingError.index] = v;

  EloRatingEvent({
    required double oldRating,
    required ShootingMatch match,
    MatchStage? stage,
    required RelativeScore score,
    required RelativeScore matchScore,
    Map<String, List<dynamic>> info = const {},
    required double ratingChange,
    double error = 0,
    required double baseK,
    required double effectiveK,
    required double backRatingError,
  }) : super(wrappedEvent: DbRatingEvent(
    ratingChange: ratingChange,
    oldRating: oldRating,
    matchId: match.sourceIds.first,
    stageNumber: stage?.stageId ?? -1,
    entryId: score.shooter.entryId,
    score: DbRelativeScore.fromHydrated(score),
    matchScore: DbRelativeScore.fromHydrated(matchScore),
    date: match.date,
    intDataElements: 0,
    doubleDataElements: _DoubleKeys.values.length,
  )) {
    this.info = info;
    wrappedEvent.setMatch(DbShootingMatch.from(match), save: false);
  }

  EloRatingEvent.wrap(DbRatingEvent event) :
    super(wrappedEvent: event);

  EloRatingEvent.copy(EloRatingEvent other) :
      super.copy(other) {
    this.error = other.error;
    this.oldRating = other.oldRating;
    this.ratingChange = other.ratingChange;
    this.baseK = other.baseK;
    this.effectiveK = other.effectiveK;
    this.backRatingError = other.backRatingError;
  }

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