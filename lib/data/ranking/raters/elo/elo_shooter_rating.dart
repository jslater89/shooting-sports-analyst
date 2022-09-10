import 'dart:math';

import 'package:collection/collection.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/ranking/model/rating_change.dart';
import 'package:uspsa_result_viewer/data/ranking/rater_types.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/elo/elo_rating_change.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/elo/multiplayer_percent_elo_rater.dart';

class EloShooterRating extends ShooterRating<EloShooterRating> {
  static double errorScale = MultiplayerPercentEloRater.defaultScale;

  double rating;
  double variance = 0;
  double trend = 0;

  double get meanSquaredError {
    return meanSquaredErrorWithWindow(window: ratingEvents.length);
  }

  double meanSquaredErrorWithWindow({int window = ShooterRating.baseTrendWindow, int offset = 0}) {
    late List<RatingEvent> events;
    if((window + offset) >= ratingEvents.length) {
      if(offset < (ratingEvents.length)) events = ratingEvents.sublist(0, ratingEvents.length - offset);
      else events = ratingEvents;
    }
    else {
      events = ratingEvents.sublist(ratingEvents.length - (window + offset), ratingEvents.length - offset);
    }

    double squaredSum = events.map((e) {
      e as EloRatingEvent;
      return pow(e.error, 2) as double;
    }).sum;

    return squaredSum / events.length;
  }

  double get normalizedError {
    return normalizedErrorWithWindow(window: ratingEvents.length);
  }

  double normalizedErrorWithWindow({int window = ShooterRating.baseTrendWindow, int offset = 0}) {
    // magic number: seems to generate something reasonable
    return meanSquaredErrorWithWindow(window: window, offset: offset) * (errorScale);
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
    double totalChange = changes.map((c) => (c as EloRatingEvent).ratingChange).sum;

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