/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/data/database/schema/ratings/db_rating_event.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/db_relative_score.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_change.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_system.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/glicko2/glicko2_rater.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/glicko2/glicko2_settings.dart';
import 'package:shooting_sports_analyst/data/sport/model.dart';

enum _IntKeys {
  /// The number of stages in the match in this event.
  stages,
}

enum _DoubleKeys {
  oldRD,
  oldInternalRating,
  rdChange,
  oldVolatility,
  volatilityChange,
  internalRatingChange,
}

class Glicko2RatingEvent extends RatingEvent {
  Glicko2RatingEvent({
    required this.settings,
    required ShootingMatch match,
    MatchStage? stage,
    required RelativeScore score,
    required RelativeScore matchScore,
    List<String> infoLines = const [],
    List<RatingEventInfoElement> infoData = const [],
    required double ratingChange,
    required double internalRatingChange,
    required double oldRating,
    required double oldInternalRating,
    required double oldVolatility,
    required double volatilityChange,
    required double oldRD,
    required double rdChange,
  }) : super(wrappedEvent: DbRatingEvent(
    ratingChange: ratingChange,
    oldRating: oldRating,
    matchId: match.sourceIds.first,
    stageNumber: stage?.stageId ?? -1,
    score: DbRelativeScore.fromHydrated(score),
    matchScore: DbRelativeScore.fromHydrated(matchScore),
    entryId: score.shooter.entryId,
    date: match.date,
    intDataElements: _IntKeys.values.length,
    doubleDataElements: _DoubleKeys.values.length,
    infoLines: infoLines,
    infoData: infoData,
  )) {
    this.oldRD = oldRD;
    this.rdChange = rdChange;
    this.oldVolatility = oldVolatility;
    this.oldInternalRating = oldInternalRating;
    this.internalRatingChange = internalRatingChange;
    this.volatilityChange = volatilityChange;
    wrappedEvent.setMatchId(match.sourceIds.first, load: false);
  }

  double get oldRD => wrappedEvent.doubleData[_DoubleKeys.oldRD.index];
  set oldRD(double v) => wrappedEvent.doubleData[_DoubleKeys.oldRD.index] = v;

  double get oldInternalRating => wrappedEvent.doubleData[_DoubleKeys.oldInternalRating.index];
  set oldInternalRating(double v) => wrappedEvent.doubleData[_DoubleKeys.oldInternalRating.index] = v;

  double get rdChange => wrappedEvent.doubleData[_DoubleKeys.rdChange.index];
  set rdChange(double v) => wrappedEvent.doubleData[_DoubleKeys.rdChange.index] = v;

  double get oldVolatility => wrappedEvent.doubleData[_DoubleKeys.oldVolatility.index];
  set oldVolatility(double v) => wrappedEvent.doubleData[_DoubleKeys.oldVolatility.index] = v;

  double get volatilityChange => wrappedEvent.doubleData[_DoubleKeys.volatilityChange.index];
  set volatilityChange(double v) => wrappedEvent.doubleData[_DoubleKeys.volatilityChange.index] = v;

  double get internalRatingChange => wrappedEvent.doubleData[_DoubleKeys.internalRatingChange.index];
  set internalRatingChange(double v) => wrappedEvent.doubleData[_DoubleKeys.internalRatingChange.index] = v;

  int get stages => wrappedEvent.intData[_IntKeys.stages.index];
  set stages(int v) => wrappedEvent.intData[_IntKeys.stages.index] = v;

  Glicko2RatingEvent.wrap(DbRatingEvent event, {required this.settings}) :
    super(wrappedEvent: event) {
    this.settings = settings;
  }

  double get oldDisplayRD => oldRD * Glicko2Settings.defaultScalingFactor;
  double get newRd => oldRD + rdChange;
  double get newDisplayRD => newRd * Glicko2Settings.defaultScalingFactor;
  double get newVolatility => oldVolatility + volatilityChange;
  double get newInternalRating => oldInternalRating + internalRatingChange;

  Glicko2Settings settings;

  @override
  void apply(RatingChange change) {
    // Glicko2-specific keys
    oldRD = change.change[Glicko2Rater.oldRDKey]!;
    rdChange = change.change[Glicko2Rater.rdChangeKey]!;
    oldVolatility = change.change[Glicko2Rater.oldVolatilityKey]!;
    volatilityChange = change.change[Glicko2Rater.volatilityChangeKey]!;
    stages = change.change[Glicko2Rater.stagesKey]!.round();

    // Base class keys
    internalRatingChange += change.change[RatingSystem.ratingKey]!;
    ratingChange = change.change[RatingSystem.ratingKey]! * settings.scalingFactor;
    extraData = change.extraData;
    infoLines = change.infoLines;
    infoData = change.infoData;
  }

  Glicko2RatingEvent.copy(Glicko2RatingEvent other) :
    this.settings = other.settings, super.copy(other) {
    this.oldRD = other.oldRD;
    this.rdChange = other.rdChange;
    this.oldVolatility = other.oldVolatility;
    this.volatilityChange = other.volatilityChange;
  }
}