import 'dart:math';

import 'package:collection/collection.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/ranking/model/rating_change.dart';
import 'package:uspsa_result_viewer/data/ranking/rater_types.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/elo/elo_rating_change.dart';

class EloShooterRating extends ShooterRating<EloShooterRating> {
  double rating;
  double variance = 0;
  double trend = 0;

  double get meanSquaredError {
    double squaredSum = ratingEvents.map((e) {
      e as EloRatingEvent;
      return pow(e.error, 2) as double;
    }).sum;

    return sqrt(squaredSum);
  }

  List<RatingEvent> ratingEvents = [];

  EloShooterRating(Shooter shooter, this.rating, {DateTime? date}) :
      super(shooter, date: date);

  void updateFromEvents(List<RatingEvent> events) {
    for(var e in events) {
      e as EloRatingEvent;
      ratingEvents.add(e);
      rating += e.ratingChange;
    }
  }

  void updateTrends(List<RatingEvent> changes) {
    double totalChange = changes.map(
            (c) => (c as EloRatingEvent).ratingChange).sum;

    var trendWindow = min(ratingEvents.length, ShooterRating.baseTrendWindow);

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

  void copyRatingFrom(EloShooterRating other) {
    super.copyRatingFrom(other);
    this.rating = other.rating;
    this.variance = other.variance;
    this.trend = other.trend;
    this.ratingEvents = other.ratingEvents.map((e) => EloRatingEvent.copy(e as EloRatingEvent)).toList();
  }

  EloShooterRating.copy(EloShooterRating other) :
        this.rating = other.rating,
        this.variance = other.variance,
        this.trend = other.trend,
        this.ratingEvents = other.ratingEvents.map((e) => EloRatingEvent.copy(e as EloRatingEvent)).toList(),
        super.copy(other);

  @override
  String toString() {
    return "${shooter.getName(suffixes: false)} ${rating.round()} ($hashCode)";
  }
}