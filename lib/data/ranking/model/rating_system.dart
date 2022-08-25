import 'package:uspsa_result_viewer/data/match/relative_scores.dart';
import 'package:uspsa_result_viewer/data/match/shooter.dart';
import 'package:uspsa_result_viewer/data/ranking/model/rating_change.dart';
import 'package:uspsa_result_viewer/data/ranking/model/rating_mode.dart';
import 'package:uspsa_result_viewer/data/ranking/model/shooter_rating.dart';

abstract class RatingSystem {
  double get defaultRating;
  RatingMode get mode;

  /// Given some number of shooters (see [RatingMode]), update their ratings
  /// and return a map of the changes.
  ///
  /// [shooter] is the shooter or shooters whose ratings should change. If
  /// [mode] is [RatingMode.roundRobin], [shooters] and [scores] both contain
  /// two elements, for the pair of shooters being compared.
  ///
  /// If [mode] is [RatingMode.oneShot], [shooters] is a one-element list containing
  /// the shooter currently under consideration, and [scores] contains entries for
  /// all shooters in the rating event.
  ///
  /// If [mode] is [RatingMode.wholeEvent], [shooters] and [scores] both contain
  /// entries for all shooters in the rating event.
  Map<ShooterRating, RatingChange> updateShooterRatings({required List<ShooterRating> shooters, required Map<ShooterRating, RelativeScore> scores, double matchStrengthMultiplier = 1.0, double connectednessMultiplier = 1.0, double eventWeightMultiplier = 1.0});

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

  static const initialClassRatings = {
    Classification.GM: 1300.0,
    Classification.M: 1200.0,
    Classification.A: 1100.0,
    Classification.B: 1000.0,
    Classification.C: 900.0,
    Classification.D: 800.0,
    Classification.U: 900.0,
    Classification.unknown: 800.0,
    null: 800.0,
  };
}