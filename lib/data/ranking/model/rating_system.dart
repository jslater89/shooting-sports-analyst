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
import 'package:shooting_sports_analyst/data/ranking/raters/glicko2/glicko2_rater.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/latentlog/latent_log_rater.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/marbles/marble_rater.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/openskill/openskill_rater.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/points/points_rater.dart';
import 'package:shooting_sports_analyst/data/ranking/rating_system_ui_data.dart';
import 'package:shooting_sports_analyst/data/ranking/scaling/rating_scaler.dart';
import 'package:shooting_sports_analyst/data/ranking/scaling/standardized_maximum_scaler.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/scoring.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/shooter.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_sorts.dart';
import 'package:shooting_sports_analyst/util.dart';

part 'rating_system.g.dart';

/// A rating system implements the core logic for a particular rating algorithm.
/// It is responsible for updating ratings given a set of shooters and scores in one
/// of several modes. (See [RatingMode].)
///
/// It may also generate predictions for a set of shooters, and validate predictions
/// against actual results.
///
/// A rating system has a few ancillary classes, two of which are given as generic
/// type parameters: [T] is the type of a [ShooterRating] class that holds the history
/// for a particular competitor, and [S] is the type of a [RaterSettings] class that
/// holds configuration parameters for the rating system.
abstract class RatingSystem<T extends ShooterRating, S extends RaterSettings> {
  /// The change in rating from a rating event.
  static const ratingChangeKey = "rating";

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

  /// Build a no-op rating change for a competitor who should receive an event
  /// without affecting rating math (e.g. by-match DQ/partial DNF handling).
  RatingChange noOpChangeFor({
    required T shooter,
    required RelativeScore score,
    required RelativeMatchScore matchScore,
    required NonRatingResultReason reason,
  });

  /// Return true if this rating system can age ratings.
  bool hasAgedRatings() {
    return false;
  }

  /// Age the ratings of all competitors in the given rating group if necessary,
  /// based on the rating algorithm's aging rules.
  ///
  /// [project] is the rating project to age ratings for.
  /// [group] is the group within project that is under consideration.
  /// [referenceDate] is the date to use as the reference point for aging.
  /// [loadedRatings] is an iterable of shooter ratings already in memory,
  /// which should be used in preference to any ratings loaded from the database.
  ///
  /// Return a set of shooter ratings that were aged and should be persisted.
  Future<Set<DbShooterRating>> ageRatings({
    required DbRatingProject project,
    required RatingGroup group,
    required DateTime referenceDate,
    Iterable<DbShooterRating> loadedRatings = const {},
  }) async {
    return {};
  }

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

  /// Return a list of [RatingRowData] objects that correspond to the columns
  /// in the rating key.
  List<RatingRowData> buildRatingKeyData({
    DateTime? trendDate,
    RatingSortMode? sortMode,
  });

  /// Return a list of [RatingRowData] objects that correspond to the columns
  /// in the rating row.
  ///
  /// [rating] is the shooter rating to build the row data for, and will always
  /// be of type [T].
  List<RatingRowData> buildRatingRowData({
    required ShooterRating rating,
    required int place,
    DateTime? trendDate,
    RatingScaler? scaler,
    RatingSortMode? sortMode,
  });

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
    return defaultRatingFormatter(rating.rating);
  }

  /// Scale a rating to a new range, if the rating system has a scaling
  /// factor or offset.
  ///
  /// The default implementation returns the rating unchanged.
  double scaleRating(double rating) {
    return rating;
  }

  /// Scale a number to a new range, if the rating system has a scaling
  /// factor or offset. This is used to scale e.g. ratings changes, where
  /// applying a scale factor is necessary but an offset would be incorrect.
  ///
  /// The default implementation returns the number unchanged.
  double scaleNumber(double number) {
    return number;
  }

  /// Return a standard scaler for this rating system for combining ratings across multiple groups. The default implementation
  /// returns an Elo-like scaler that maps the minimum rating to 0 and the maximum rating to 2000.
  RatingScaler get standardScaler => StandardizedMaximumScaler(info: null, scaleMin: 0, scaleMax: 2000);

  /// Return a representation of a numeric rating suitable for display in e.g.
  /// a table.
  ///
  /// The default implementation returns a whole number string for numbers >100,
  /// 1 decimal place for numbers >10, 2 decimal places for numbers >1, and 3
  /// decimal places otherwise, mirrored on the other side of zero.
  String formatNumericRating(double rating) {
    return defaultRatingFormatter(rating);
  }

  /// Return a representation of a numeric rating change suitable for display in e.g.
  /// a table.
  ///
  /// The default implementation calls [formatNumericRating] on the rating change.
  /// Rating systems with scaling factors or offsets may need an alternative implementation.
  String formatNumericRatingChange(double ratingChange) {
    return defaultRatingFormatter(ratingChange);
  }

  /// Return [AlgorithmPrediction]s for the list of shooters.
  ///
  /// Provide a [seed] for repeatable predictions, if desired. [matchDate] may improve
  /// the accuracy of some predictions that use date-based factors.
  List<AlgorithmPrediction> predict(List<ShooterRating> ratings, {int? seed, DateTime? matchDate}) {
    throw UnimplementedError();
  }

  /// Given a delta between two ratings, estimate the ratio for the lower-rated shooter.
  ///
  /// Use [settings] to specify the rater settings to use, or else use the settings
  /// of this algorithm instance.
  double estimateRatioFloor(double ratingDelta, {RaterSettings? settings}) {
    throw UnimplementedError();
  }

  static const double defaultRatioFloor = 0;
  static const double defaultRatioMult = 1;

  /// Return true if this rating system can generate predictions.
  bool get supportsPrediction => false;

  /// Return the prediction settings for this rating system.
  PredictionSettings get predictionSettings => PredictionSettings();

  /// Return true if this rating system's predictions are given in ratios
  /// (i.e. 0-1 scores where 1.0 is the winner and everyone else is their
  /// proportional expected score).
  bool get predictionsOutputRatios => false;

  /// Return true if this rating system can estimate ratio gaps.
  bool get supportsRatioFloor => false;

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
      case DbRatingProject.glicko2Value:
        return Glicko2Rater.fromJson(encodedProject);
      case DbRatingProject.latentLogValue:
        return LatentLogRater.fromJson(encodedProject);
      default:
        throw ArgumentError();
    }
  }
}

enum NonRatingResultReason {
  dq,
  dnf,
  singleEntry;
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

class PredictionSettings {
  /// True if the prediction's internal score values are result ratios (0-1) where 1.0 is the winner and everyone else is their proportional expected score.
  /// Default false.
  final bool outputsAreRatios;

  /// True if the prediction's internal score values are result percentages (0-100) where 100 is the winner and everyone else is their proportional expected score.
  /// Default false.
  final bool outputsArePercentages;

  /// A multiplier for the prediction's sigma value when calculating place probabilities, default 2.0.
  final double placeSigmaMultiplier;

  /// A multiplier for the prediction's sigma value when calculating percent probabilities, default 2.0. Unused in
  /// favor of [placeSigmaMultiplier].
  final double percentSigmaMultiplier;

  /// A multiplier for the prediction's sigma value when calculating spread probabilities, default 2.0. Unused in
  /// favor of [placeSigmaMultiplier].
  final double spreadSigmaMultiplier;

  PredictionSettings({
    this.outputsAreRatios = false,
    this.outputsArePercentages = false,
    this.placeSigmaMultiplier = 2.0,
    this.percentSigmaMultiplier = 2.0,
    this.spreadSigmaMultiplier = 2.0,
  });
}

/// The default implementation of [formatNumericRating] and [formatNumericRatingChange],
/// which returns a string with at least 3 significant digits if the rating is finite,
/// and otherwise returns "(n/a)".
///
/// Numbers with more than 3 significant digits on the left of the decimal point are
/// rounded to the nearest integer. Numbers with fewer than 3 significant digits on the
/// left side of the decimal point return a string with a total of 3 significant digits
/// between the left and right of the decimal point.
final defaultRatingFormatter = (double rating) {
  if(rating.isFinite) {
    return rating.toStringWithSignificantDigits(3);
  }
  else {
    return "(n/a)";
  }
};