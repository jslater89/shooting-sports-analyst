/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/db_rating_event.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_change.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_mode.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_settings.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/match_prediction.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/elo/multiplayer_percent_elo_rater.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/marbles/marble_rater.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/openskill/openskill_rater.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/points/points_rater.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/scoring.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/shooter.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/ui/rater/rater_view.dart';
import 'package:shooting_sports_analyst/ui/widget/score_row.dart';

abstract class RatingSystem<T extends ShooterRating, S extends RaterSettings, C extends RaterSettingsController<S>> {
  /// Use in rating changes
  static const ratingKey = "rating";

  RatingMode get mode;
  bool get byStage;

  /// Given some number of shooters (see [RatingMode]), update their ratings
  /// and return a map of the changes.
  ///
  /// [isMatchOngoing] tells the rating engine that a match is in progress for
  /// ratings purposes: match blend will be disabled and certain DNFs will be
  /// ignored.
  ///
  /// [shooter] is the shooter or shooters whose ratings should change. [scores]
  /// is a list of scores for the rating event in question. [matchScores] is a list
  /// of match totals, which is identical to [scores] if byStage is false. The scores
  /// maps are sorted by finish order.
  ///
  /// If [mode] is [RatingMode.roundRobin], [shooters] and [scores] both contain
  /// two elements, for the pair of shooters being compared.
  ///
  /// If [mode] is [RatingMode.oneShot], [shooters] is a one-element list containing
  /// the shooter currently under consideration, and [scores] contains entries for
  /// all shooters in the rating event.
  ///
  /// If [mode] is [RatingMode.wholeEvent], [shooters] and [scores] both contain
  /// entries for all shooters in the rating event.
  Map<ShooterRating, RatingChange> updateShooterRatings({
    required ShootingMatch match,
    bool isMatchOngoing = false,
    required List<ShooterRating> shooters,
    required Map<ShooterRating, RelativeScore> scores,
    required Map<ShooterRating, RelativeMatchScore> matchScores,
    double matchStrengthMultiplier = 1.0,
    double connectednessMultiplier = 1.0,
    double eventWeightMultiplier = 1.0
  });

  // ****** Self-describing data classes ******

  /// Return a deep copy of the provided shooter rating.
  ShooterRating copyShooterRating(T rating);

  /// Create a new shooter rating for the given information.
  ShooterRating newShooterRating(MatchEntry shooter, {required Sport sport, required DateTime date});

  /// Given a database shooter rating, return a typed shooter rating that
  /// wraps it.
  T wrapDbRating(DbShooterRating rating);

  RatingEvent newEvent({
    required ShootingMatch match,
    MatchStage? stage,
    required ShooterRating rating,
    required RelativeScore score,
    required RelativeMatchScore matchScore,
    List<String> infoLines = const [],
    List<RatingEventInfoElement> infoData = const [],
  });

  /// Return a string containing a CSV representation of the
  /// given shooter ratings.
  String ratingsToCsv(List<ShooterRating> ratings);
  void encodeToJson(Map<String, dynamic> json);

  /// Return the current settings for this rating system.
  S get settings;

  // ****** Self-describing UI ******

  List<RatingSortMode> get supportedSorts => RatingSortMode.values;
  int Function(ShooterRating a, ShooterRating b)? comparatorFor(RatingSortMode mode, {DateTime? changeSince}) {
    return null;
  }
  String nameForSort(RatingSortMode mode) {
    return mode.uiLabel;
  }

  /// The size of buckets in a shooter rating histogram for the given parameters.
  int histogramBucketSize({required int shooterCount, required int matchCount, required double minRating, required double maxRating}) {
    return 100;
  }

  /// Return a new instance of a [RaterSettingsController] subclass for
  /// the given rater type, which allows the UI to retrieve settings and
  /// restore defaults.
  RaterSettingsController<S> newSettingsController();

  /// Return a widget tree which can be inserted into a child of a Column
  /// wrapped in a SingleChildScrollView, which implements the settings for this
  /// rating system.
  RaterSettingsWidget<S, C> newSettingsWidget(C controller);

  /// Return a Row containing labels for a table of shooter ratings.
  Row buildRatingKey(BuildContext context, {DateTime? trendDate});

  /// Return a ScoreRow containing values for a given shooter rating in a table of shooter ratings.
  ///
  /// [rating] is guaranteed to be the subclass of ShooterRating corresponding to this
  /// rating system.
  ///
  /// If [trendDate] is provided, the rating change since that date should be displayed in
  /// place of the last-30-events trend.
  ScoreRow buildRatingRow({required BuildContext context, required int place, required ShooterRating rating, DateTime? trendDate});

  /// Return ShooterPredictions for the list of shooters.
  ///
  /// Provide a [seed] for repeatable predictions, if desired.
  List<ShooterPrediction> predict(List<ShooterRating> ratings, {int? seed}) {
    throw UnimplementedError();
  }

  /// Return true if this rating system can generate predictions.
  bool get supportsPrediction => false;

  /// Return an error measure for the given predictions and result.
  PredictionOutcome validate({
    required List<ShooterRating> shooters,
    required Map<ShooterRating, RelativeScore> scores,
    required Map<ShooterRating, RelativeMatchScore> matchScores,
    required List<ShooterPrediction> predictions,
    bool chatty = true,
  }) {
    throw UnimplementedError();
  }

  /// Return true if this rating system can validate predictions.
  bool get supportsValidation => false;

  static const initialPlacementMultipliers = [
    // 1.5,
    // 1.5,
    // 1.5,
    // 1.5,
    // 1.5,
    // 1.5,
    // 1.5,
    // 1.5,
    // 1.5,
    // 1.5,
    2.5,
    2.25,
    2.0,
    1.75,
    1.625,
    1.5,
    1.4,
    1.3,
    1.2,
    1.1,
  ];

  static const _multiplayerEloValue = "multiElo";
  static const _openskillValue = "openskill";
  static const _pointsValue = "points";
  static const _marblesValue = "marbles";

  static RatingSystem algorithmForName(String name, Map<String, dynamic> encodedProject) {
    switch(name) {
      case _multiplayerEloValue:
        return MultiplayerPercentEloRater.fromJson(encodedProject);
      case _pointsValue:
        return PointsRater.fromJson(encodedProject);
      case _openskillValue:
        return OpenskillRater.fromJson(encodedProject);
      case _marblesValue:
        return MarbleRater.fromJson(encodedProject);
      default:
        throw ArgumentError();
    }
  }
}

class PredictionOutcome {
  double error;
  Map<ShooterPrediction, SimpleMatchResult> actualResults;

  /// True if the [RatingSystem] changed the prediction inputs
  /// to generate more complete data about its accuracy, in
  /// particular if not all shooters registered.
  bool mutatedInputs;

  PredictionOutcome({
    required this.error,
    required this.actualResults,
    required this.mutatedInputs,
  });
}

class SimpleMatchResult {
  double raterScore;
  double percent;
  int place;

  SimpleMatchResult({
    required this.raterScore,
    required this.percent,
    required this.place,
  });
}