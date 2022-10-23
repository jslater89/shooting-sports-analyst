import 'dart:math';

import 'package:collection/collection.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/ranking/rater_types.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/elo/elo_rating_change.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/elo/multiplayer_percent_elo_rater.dart';

class EloShooterRating extends ShooterRating<EloShooterRating> {
  static double errorScale = MultiplayerPercentEloRater.defaultScale;

  double rating;
  double variance = 0;

  double get shortTrend => rating - averageRating(window: ShooterRating.baseTrendWindow ~/ 2).firstRating;
  double get mediumTrend => rating - averageRating(window: ShooterRating.baseTrendWindow).firstRating;
  double get longTrend => rating - averageRating(window: ShooterRating.baseTrendWindow * 2).firstRating;

  // double get trend => (shortTrend + mediumTrend + longTrend) / 3;

  double get meanSquaredError {
    return meanSquaredErrorWithWindow(window: ratingEvents.length);
  }

  double meanSquaredErrorWithWindow({int window = ShooterRating.baseTrendWindow, int offset = 0}) {
    // With default settings, this yields a starting normalized error of 400,
    // which more or less jives with observation.
    if(ratingEvents.isEmpty) return 0.5;

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

  double decayingErrorWithWindow({
    int window = ShooterRating.baseTrendWindow * 2,
    int fullEffect = ShooterRating.baseTrendWindow,
    int offset = 0,
    double decayAfterFull = 0.9,
  }) {
    if(ratingEvents.isEmpty) return 0.5;

    late List<RatingEvent> events;
    if((window + offset) >= ratingEvents.length) {
      if(offset < (ratingEvents.length)) events = ratingEvents.sublist(0, ratingEvents.length - offset);
      else events = ratingEvents;
    }
    else {
      events = ratingEvents.sublist(ratingEvents.length - (window + offset), ratingEvents.length - offset);
    }

    double currentDecay = 1.0;
    double squaredSum = 0.0;
    double length = 0.0;
    var reversed = events.reversed.toList();
    for(int i = 0; i < reversed.length; i++) {
      var e = reversed[i] as EloRatingEvent;
      if(i >= fullEffect) {
        currentDecay *= decayAfterFull;
      }

      squaredSum += pow(e.error, 2) * currentDecay;
      length += 1.0 * currentDecay;
    }
    return squaredSum / length;
  }

  double get normalizedError {
    return normalizedErrorWithWindow(window: ratingEvents.length);
  }

  double normalizedErrorWithWindow({int window = ShooterRating.baseTrendWindow, int offset = 0}) {
    // Using scale as the magic number seems to generate something useful
    return meanSquaredErrorWithWindow(window: window, offset: offset) * (errorScale);
  }

  double normalizedDecayingErrorWithWindow({
    int window = ShooterRating.baseTrendWindow * 2,
    int fullEffect = ShooterRating.baseTrendWindow,
    int offset = 0,
    double decayAfterFull = 0.9,
  }) {
    // Using scale as the magic number seems to generate something useful
    return decayingErrorWithWindow(window: window, fullEffect: fullEffect, offset: offset, decayAfterFull: decayAfterFull) * (errorScale);
  }

  double get standardError => normalizedDecayingErrorWithWindow(
    window: (ShooterRating.baseTrendWindow * 1.5).round(),
    fullEffect: ShooterRating.baseTrendWindow,
  );

  double standardErrorWithOffset({int offset = 0}) {
    return normalizedDecayingErrorWithWindow(
      window: (ShooterRating.baseTrendWindow * 1.5).round(),
      fullEffect: ShooterRating.baseTrendWindow,
      offset: offset,
    );
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
    var trendWindow = min(ratingEvents.length, ShooterRating.baseTrendWindow);

    var events = ratingEvents.sublist(ratingEvents.length - trendWindow);

    if(trendWindow == 0) {
      return;
    }

    var stdDev = sqrt(events.map((e) => pow(e.ratingChange, 2)).sum / (events.length - 1));

    variance = stdDev;

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
    this.ratingEvents = other.ratingEvents.map((e) => EloRatingEvent.copy(e as EloRatingEvent)).toList();
  }

  EloShooterRating.copy(EloShooterRating other) :
        this.rating = other.rating,
        this.variance = other.variance,
        this.ratingEvents = other.ratingEvents.map((e) => EloRatingEvent.copy(e as EloRatingEvent)).toList(),
        super.copy(other);

  @override
  String toString() {
    return "${shooter.getName(suffixes: false)} ${rating.round()} ($hashCode)";
  }
}