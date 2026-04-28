
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:shooting_sports_analyst/data/ranking/model/career_stats.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_change.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/elo/elo_shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/glicko2/glicko2_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/glicko2/glicko2_rating_event.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/latentlog/latent_log_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/latentlog/latent_log_rating_event.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/openskill/openskill_rating.dart';

AccumulatedRatingResult accumulateRatingEvents({
  required ShooterRating rating,
  required CareerStats careerStats,
  required PeriodicStats displayedStats,
}) {
  double accumulator = 0;
  double minRating = 10000000;
  double maxRating = -10000000;
  double minWithError = 10000000;
  double maxWithError = -10000000;

  Map<int, int> yearIndices = {};

  // Raters may provide alternate chart values to avoid the Glicko-2 problem
  // where rating immediately jumps to the correct value and the Y axis ends
  // up only showing 100-200 rating points of range.
  double? maximumMinimum;
  double? minimumMaximum;

  if(rating is Glicko2Rating) {
    // For Glicko-2, always include 1500 in the range
    minimumMaximum = 1500;
    maximumMinimum = 1500;
  }
  else if(rating is LatentLogRating) {
    final o = rating.settings.scaleOffset;
    minimumMaximum = o;
    maximumMinimum = o;
  }
  else if(rating is EloShooterRating && careerStats.isAnnualStats(displayedStats)) {
    // minimumMaximum = 1000;
    // maximumMinimum = 1000;
  }
  // Elo doesn't really have this problem because the initial rating jump is usually
  // much smaller.

  var eventsOfInterest = displayedStats.events.reversed.where((e) => e.newRating != 0 && e.ratingChange != 0);
  // Map from year to index of first event in that year,
  // used to show year separators.
  final events = eventsOfInterest.mapIndexed((i, e) {

    // Update year indices
    // We're starting at the beginning, so the first event we see with a given
    // year is the index we care about.
    if(!yearIndices.containsKey(e.wrappedEvent.date.year)) {
      yearIndices[e.wrappedEvent.date.year] = i;
    }

    final measureRating = chartMeasureForShooterEvent(rating, e);
    if(measureRating < minRating) minRating = measureRating;
    if(measureRating > maxRating) maxRating = measureRating;

    double error = 0;
    if(rating is EloShooterRating) {
      error = rating.standardErrorWithOffset(offset: eventsOfInterest.length - (i + 1));

      // print("Comparison: ${error.toStringAsFixed(2)} vs ${e2.toStringAsFixed(2)}");
    }
    else if(rating is OpenskillRating) {
      error = rating.sigmaWithOffset(eventsOfInterest.length - (i + 1)) / 2;
    }
    else if(rating is Glicko2Rating) {
      e as Glicko2RatingEvent;
      error = e.newDisplayRD / 2;
    }
    else if(rating is LatentLogRating) {
      e as LatentLogRatingEvent;
      error = sqrt(e.newVariance) * e.settings.scaleFactor / 2;
    }

    var plusError = measureRating + error;
    var minusError = measureRating - error;
    if(plusError > maxWithError) maxWithError = plusError;
    if(minusError < minWithError) minWithError = minusError;

    return AccumulatedRatingEvent(e, accumulator += _chartRatingChangeForShooter(rating, e), error);
  }).toList();


  return AccumulatedRatingResult(
    rating: rating,
    maximumMinimum: maximumMinimum,
    minimumMaximum: minimumMaximum,
    minWithError: minWithError,
    maxWithError: maxWithError,
    yearIndices: yearIndices,
    events: events,
  );
}

class AccumulatedRatingResult {
  final ShooterRating rating;
  double? maximumMinimum;
  double? minimumMaximum;
  double minWithError;
  double maxWithError;

  double get minimumChartValue {
    if(maximumMinimum != null) {
      return min(maximumMinimum!, minWithError * 0.95);
    }
    return minWithError * 0.95;
  }

  double get maximumChartValue {
    if(minimumMaximum != null) {
      return max(minimumMaximum!, maxWithError * 1.05);
    }
    return maxWithError * 1.05;
  }

  Map<int, int> yearIndices;
  List<AccumulatedRatingEvent> events;

  AccumulatedRatingResult({
    required this.rating,
    required this.maximumMinimum,
    required this.minimumMaximum,
    required this.minWithError,
    required this.maxWithError,
    required this.yearIndices,
    required this.events,
  });
}

class AccumulatedRatingEvent {
  RatingEvent baseEvent;
  double accumulated;
  double errorAt;
  DateTime get date => baseEvent.date;

  AccumulatedRatingEvent(this.baseEvent, this.accumulated, this.errorAt);
}


double _chartRatingChangeForShooter(ShooterRating shooterRating, RatingEvent e) {
  if(shooterRating is LatentLogRating) {
    return e.ratingChange * shooterRating.settings.scaleFactor;
  }
  return e.ratingChange;
}

double chartMeasureForShooterEvent(ShooterRating shooterRating, RatingEvent e) {
  if(shooterRating is LatentLogRating) {
    return (e as LatentLogRatingEvent).newDisplayRating;
  }
  return e.newRating;
}