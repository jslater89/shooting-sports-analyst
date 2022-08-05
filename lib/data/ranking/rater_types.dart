import 'dart:math';

import 'package:uspsa_result_viewer/data/model.dart';

class ShooterRating {
  static const baseTrendWindow = 6;

  final Shooter shooter;
  double rating;
  double variance = 0;
  double trend = 0;

  List<RatingEvent> ratingEvents = [];

  ShooterRating(this.shooter, this.rating);

  void updateTrends(double totalChange) {
    var trendWindow = min(ratingEvents.length, baseTrendWindow * 5);

    if(trendWindow == 0) {
      return;
    }

    var totalVariance = variance * (trendWindow - 1) + totalChange.abs();
    variance = totalVariance / (trendWindow.toDouble());

    var totalTrend = trend * (trendWindow - 1) + (totalChange >= 0 ? 1 : -1);
    trend = totalTrend / (trendWindow);

    // if(Rater.processMemberNumber(shooter.memberNumber) == "128393") {
    //   debugPrint("Trends for ${shooter.lastName}");
    //   debugPrint("$totalVariance / $trendWindow = $variance");
    //   debugPrint("$totalTrend / $trendWindow = $trend");
    // }
  }
  
  void copyRatingFrom(ShooterRating other) {
    this.rating = other.rating;
    this.variance = other.variance;
    this.trend = other.trend;
    this.ratingEvents = other.ratingEvents.map((e) => RatingEvent.copy(e)).toList();
  }

  ShooterRating.copy(ShooterRating other) :
      this.shooter = other.shooter,
      this.rating = other.rating,
      this.variance = other.variance,
      this.trend = other.trend,
      this.ratingEvents = other.ratingEvents.map((e) => RatingEvent.copy(e)).toList();

  @override
  String toString() {
    return "${shooter.getName(suffixes: false)} ${rating.round()} ($hashCode)";
  }
}

class RatingChange {
  final double change;
  final List<String> info;

  RatingChange({required this.change, this.info = const []});
}

class RatingEvent {
  String eventName;
  RelativeScore score;
  double ratingChange;
  List<String> info;

  RatingEvent({required this.eventName, required this.score, this.ratingChange = 0, this.info = const []});

  RatingEvent.copy(RatingEvent other) :
      this.eventName = other.eventName,
      this.score = other.score,
      this.ratingChange = other.ratingChange,
      this.info = [...other.info];
}

enum RatingMode {
  /// This rating system compares every shooter pairwise with every other shooter.
  /// [RatingSystem.updateShooterRatings]' scores parameter will contain two shooters
  /// to be compared.
  roundRobin,

  /// This rating system considers each shooter once per rating event, and does any
  /// additional iteration internally. [RatingSystem.updateShooterRatings]' scores
  /// parameter will contain scores for all shooters.
  oneShot,
}

abstract class RatingSystem {
  double get defaultRating;
  RatingMode get mode;

  /// Given some number of shooters (see [RatingMode]), update their ratings
  /// and return a map of the changes.
  ///
  /// [shooter] is the shooter or shooters whose ratings should change. If
  /// [mode] is [RatingMode.roundRobin], [shooters] is identical to the list
  /// of keys in [scores].
  ///
  /// [match] is the match and [stage] the stage in question. If [stage] is
  /// not null, the ratings are being done by stage.
  Map<ShooterRating, RatingChange> updateShooterRatings({required List<ShooterRating> shooters, required Map<ShooterRating, RelativeScore> scores, double matchStrength = 1.0});

  static const initialPlacementMultipliers = [
    2.5,
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
    Classification.GM: 1300,
    Classification.M: 1200,
    Classification.A: 1100,
    Classification.B: 1000,
    Classification.C: 900,
    Classification.D: 800,
  };
}