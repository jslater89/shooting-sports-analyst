import 'package:uspsa_result_viewer/data/model.dart';

class ShooterRating {
  final Shooter shooter;
  double rating;

  List<RatingEvent> ratingEvents = [];

  ShooterRating(this.shooter, this.rating);

  ShooterRating.copy(ShooterRating other) :
      this.shooter = other.shooter,
      this.rating = other.rating,
      this.ratingEvents = other.ratingEvents.map((e) => RatingEvent.copy(e)).toList();
}

class RatingEvent {
  String eventName;
  RelativeScore score;
  double ratingChange;

  RatingEvent({required this.eventName, required this.score, this.ratingChange = 0});

  RatingEvent.copy(RatingEvent other) :
      this.eventName = other.eventName,
      this.score = other.score,
      this.ratingChange = other.ratingChange;
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
  Map<ShooterRating, double> updateShooterRatings({required List<ShooterRating> shooters, required Map<ShooterRating, RelativeScore> scores, double matchStrength = 1.0});

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
}