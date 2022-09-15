import 'package:flutter/material.dart';
import 'package:uspsa_result_viewer/data/match/practical_match.dart';
import 'package:uspsa_result_viewer/data/match/relative_scores.dart';
import 'package:uspsa_result_viewer/data/match/shooter.dart';
import 'package:uspsa_result_viewer/data/ranking/model/rating_change.dart';
import 'package:uspsa_result_viewer/data/ranking/model/rating_mode.dart';
import 'package:uspsa_result_viewer/data/ranking/model/rating_settings.dart';
import 'package:uspsa_result_viewer/data/ranking/model/shooter_rating.dart';
import 'package:uspsa_result_viewer/ui/score_row.dart';

abstract class RatingSystem<T extends ShooterRating<T>, S extends RaterSettings<S>, C extends RaterSettingsController<S>> {
  RatingMode get mode;
  bool get byStage;

  /// Given some number of shooters (see [RatingMode]), update their ratings
  /// and return a map of the changes.
  ///
  /// [shooter] is the shooter or shooters whose ratings should change. [scores]
  /// is a list of scores for the rating event in question. [matchScores] is a list
  /// of match totals, which is identical to [scores] if byStage is true.
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
    required List<ShooterRating> shooters,
    required Map<ShooterRating, RelativeScore> scores,
    required Map<ShooterRating, RelativeScore> matchScores,
    double matchStrengthMultiplier = 1.0,
    double connectednessMultiplier = 1.0,
    double eventWeightMultiplier = 1.0
  });

  /// Return a Row containing labels for a table of shooter ratings.
  Row buildRatingKey(BuildContext context);

  /// Return a ScoreRow containing values for a given shooter rating in a table of shooter ratings.
  ///
  /// [rating] is guaranteed to be the subclass of ShooterRating corresponding to this
  /// rating system.
  ScoreRow buildRatingRow({required BuildContext context, required int place, required ShooterRating rating});

  /// Return a deep copy of the provided shooter rating.
  ShooterRating copyShooterRating(T rating);

  /// Create a new shooter rating for the given information.
  ShooterRating newShooterRating(Shooter shooter, {DateTime? date});

  RatingEvent newEvent({
    required PracticalMatch match,
    Stage? stage,
    required ShooterRating rating, required RelativeScore score, List<String> info = const []
  });

  /// Return a string containing a CSV representation of the
  /// given shooter ratings.
  String ratingsToCsv(List<ShooterRating> ratings);

  encodeToJson(Map<String, dynamic> json);

  /// Return a new instance of a [RaterSettingsController] subclass for
  /// the given rater type, which allows the UI to retrieve settings and
  /// restore defaults.
  RaterSettingsController<S> newSettingsController();

  /// Return to get a widget tree which can be inserted into a child of a Column
  /// wrapped in a SingleChildScrollView, which implements the settings for this
  /// rating system.
  RaterSettingsWidget<S, C> newSettingsWidget(C controller);

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
}