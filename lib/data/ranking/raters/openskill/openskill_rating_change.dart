/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/db_rating_event.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/db_relative_score.dart';
import 'package:shooting_sports_analyst/data/ranking/rater_types.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/openskill/openskill_rater.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/scoring.dart';

enum _DoubleKeys {
  sigmaChange
}

class OpenskillRatingEvent extends RatingEvent {
  double get sigmaChange => wrappedEvent.doubleData[_DoubleKeys.sigmaChange.index];
  set sigmaChange(double v) => wrappedEvent.doubleData[_DoubleKeys.sigmaChange.index] = v;

  double get initialMu => super.oldRating;
  set initialMu(double v) => super.oldRating = v;

  double get muChange => super.ratingChange;
  set muChange(double v) => super.ratingChange = v;

  OpenskillRatingEvent({
    required double initialMu,
    required double muChange,
    required double sigmaChange,
    required ShootingMatch match,
    MatchStage? stage,
    required RelativeScore score,
    required RelativeScore matchScore,
    Map<String, List<dynamic>> info = const {}
  }) : super(wrappedEvent: DbRatingEvent(
    ratingChange: muChange,
    oldRating: initialMu,
    matchId: match.sourceIds.first,
    stageNumber: stage?.stageId ?? -1,
    score: DbRelativeScore.fromHydrated(score),
    matchScore: DbRelativeScore.fromHydrated(matchScore),
    entryId: score.shooter.entryId,
    date: match.date,
    intDataElements: 0,
    doubleDataElements: _DoubleKeys.values.length,
  )) {
    this.info = info;
  }

  @override
  void apply(RatingChange change) {
    muChange += change.change[OpenskillRater.muKey]!;
    sigmaChange += change.change[OpenskillRater.sigmaKey]!;
  }

  OpenskillRatingEvent.copy(OpenskillRatingEvent other) :
      super.copy(other) {
    this.initialMu = other.initialMu;
    this.muChange = other.muChange;
    this.sigmaChange = other.sigmaChange;
  }

  OpenskillRatingEvent.wrap(DbRatingEvent event) :
        super(wrappedEvent: event);
}