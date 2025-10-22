/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:json_annotation/json_annotation.dart';
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
import 'package:shooting_sports_analyst/data/ranking/model/rating_sorts.dart';
import 'package:shooting_sports_analyst/util.dart';

part 'rating_system.g.dart';

abstract class RatingSystem<T extends ShooterRating, S extends RaterSettings> {
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

  /// Return a string containing a JSON representation of the
  /// given shooter ratings.
  List<JsonShooterRating> ratingsToJson(List<ShooterRating> ratings);

  /// Encode the given shooter ratings into a JSON object.
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

  /// Return a representation of a shooter rating suitable for display in e.g.
  /// a table.
  ///
  /// The default implementation calls [formatNumericRating] on the rating's
  /// numeric rating.
  String formatRating(ShooterRating rating) {
    return "${formatNumericRating(rating.rating)}";
  }

  /// Return a representation of a numeric rating suitable for display in e.g.
  /// a table.
  ///
  /// The default implementation returns a whole number string for numbers >100,
  /// 1 decimal place for numbers >10, 2 decimal places for numbers >1, and 3
  /// decimal places otherwise, mirrored on the other side of zero.
  String formatNumericRating(double rating) {
    return rating.toStringWithSignificantDigits(3);
  }

  /// Return [AlgorithmPrediction]s for the list of shooters.
  ///
  /// Provide a [seed] for repeatable predictions, if desired.
  List<AlgorithmPrediction> predict(List<ShooterRating> ratings, {int? seed}) {
    throw UnimplementedError();
  }

  /// Given a delta between two ratings, estimate the ratio for the lower-rated shooter.
  ///
  /// Use [settings] to specify the rater settings to use, or else use the settings
  /// of this algorithm instance.
  double estimateRatioFloor(double ratingDelta, {RaterSettings? settings}) {
    throw UnimplementedError();
  }

  /// Return true if this rating system can generate predictions.
  bool get supportsPrediction => false;

  /// Return true if this rating system can estimate ratio gaps.
  bool get supportsRatioGap => false;

  /// Return an error measure for the given predictions and result.
  PredictionOutcome validate({
    required List<ShooterRating> shooters,
    required Map<ShooterRating, RelativeScore> scores,
    required Map<ShooterRating, RelativeMatchScore> matchScores,
    required List<AlgorithmPrediction> predictions,
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
  Map<AlgorithmPrediction, SimpleMatchResult> actualResults;

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

@JsonSerializable()
class JsonShooterRating {
  final String memberNumber;
  final List<String> knownMemberNumbers;
  final List<String> possibleMemberNumbers;
  final String name;
  final String division;
  final double rating;

  JsonShooterRating({
    required this.memberNumber,
    required this.name,
    required this.division,
    required this.rating,
    required this.knownMemberNumbers,
    required this.possibleMemberNumbers,
  });

  JsonShooterRating.fromShooterRating(ShooterRating rating) :
    memberNumber = rating.memberNumber,
    knownMemberNumbers = rating.knownMemberNumbers.toList(),
    possibleMemberNumbers = rating.allPossibleMemberNumbers.toList(),
    name = rating.getName(suffixes: false),
    division = rating.division?.name ?? "(unknown)",
    rating = rating.rating;

  factory JsonShooterRating.fromJson(Map<String, dynamic> json) => _$JsonShooterRatingFromJson(json);
  Map<String, dynamic> toJson() => _$JsonShooterRatingToJson(this);
}
