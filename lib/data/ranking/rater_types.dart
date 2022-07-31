import 'package:uspsa_result_viewer/data/model.dart';

class ShooterRating {
  final Shooter shooter;
  double rating;

  List<RatingEvent> ratingEvents = [];

  ShooterRating(this.shooter, this.rating);
}

class RatingEvent {
  String eventName;
  RelativeScore score;
  double ratingChange;

  RatingEvent({required this.eventName, required this.score, this.ratingChange = 0});
}

enum RatingMode {
  /// This rating system compares every shooter pairwise with every other shooter.
  /// [RatingSystem.updateShooterRatings]' scores parameter will contain two shooters
  /// to be compared.
  roundRobin,

  /// This rating system considers each shooter once per rating event, and does any
  /// additional iteration internally. [RatingSystem.updateShooterRatings]' scores
  /// parameter will contain one shooter.
  oneShot,
}

abstract class RatingSystem {
  double get defaultRating;
  RatingMode get mode;

  /// Given some number of shooters (see [RatingMode]), update their ratings
  /// and return a map of the changes.
  ///
  /// [match] is the match and [stage] the stage in question. If [stage] is
  /// not null, the ratings are being done by stage.
  Map<ShooterRating, double> updateShooterRatings(Map<ShooterRating, RelativeScore> scores, {required PracticalMatch match, Stage? stage});
}