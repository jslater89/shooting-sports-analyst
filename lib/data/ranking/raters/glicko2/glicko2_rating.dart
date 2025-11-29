/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math' show sqrt, pow, min;

import 'package:collection/collection.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/db_rating_event.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_change.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/glicko2/glicko2_rating_event.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/glicko2/glicko2_settings.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/shooter.dart';
import 'package:shooting_sports_analyst/util.dart';

enum _DoubleKeys {
  // rating and rating deviation are stored in wrappedRating.rating and wrappedRating.error
  /// The volatility parameter for this competitor.
  volatility,
  /// The current RD for this competitor, calculated on demand based on the difference between
  /// the current time and the last commit.
  currentRD,
}

enum _IntKeys {
  /// Seconds since Unix epoch for the commit time of last rating update, i.e., the
  /// timestamp of the last match.
  lastCommitTimestamp,
  /// Seconds since Unix epoch for the timestamp of the current RD calculation. If
  /// the current RD is requested and the year-month-day in this timestamp is the same
  /// as the current timestamp, the cached current RD can be returned directly.
  currentRDTimestamp,
  /// The number of stages shot.
  lengthInStages,
}

class Glicko2Rating extends ShooterRating<Glicko2RatingEvent> {
  static int? ratingPeriodLength;

  Glicko2Rating(MatchEntry shooter, {
    required super.sport,
    required super.date,
    required double initialRating,
    required double initialVolatility,
    required double initialRD,
  }) : super(
    shooter,
    intDataElements: _IntKeys.values.length,
    doubleDataElements: _DoubleKeys.values.length,
  ) {
    this.rating = initialRating;
    this.volatility = initialVolatility;
    this.currentRD = initialRD;
    this.committedRD = initialRD;
    this.lastCommitTimestamp = super.firstSeen.millisecondsSinceEpoch ~/ 1000;
    this.currentRDTimestamp = super.firstSeen.millisecondsSinceEpoch ~/ 1000;
  }

  double get volatility => wrappedRating.doubleData[_DoubleKeys.volatility.index];
  set volatility(double v) => wrappedRating.doubleData[_DoubleKeys.volatility.index] = v;

  /// This getter is current as of the current clock time.
  double get currentRD {
    if(currentRDTimestamp.isSameDay(DateTime.now())) {
      return wrappedRating.doubleData[_DoubleKeys.currentRD.index];
    }
    else {
      final updated = calculateCurrentRD();
      wrappedRating.doubleData[_DoubleKeys.currentRD.index] = updated;
      currentRDTimestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      return updated;
    }
  }
  set currentRD(double v) => wrappedRating.doubleData[_DoubleKeys.currentRD.index] = v;

  int get lastCommitTimestamp => wrappedRating.intData[_IntKeys.lastCommitTimestamp.index];
  set lastCommitTimestamp(int v) => wrappedRating.intData[_IntKeys.lastCommitTimestamp.index] = v;

  int get currentRDTimestamp => wrappedRating.intData[_IntKeys.currentRDTimestamp.index];
  set currentRDTimestamp(int v) => wrappedRating.intData[_IntKeys.currentRDTimestamp.index] = v;

  /// The RD that was calculated at the end of the last rating event commit.
  double get committedRD => wrappedRating.error;
  set committedRD(double v) => wrappedRating.error = v;

  /// The number of matches shot.
  int get lengthInMatches => wrappedRating.length;

  /// The number of stages shot.
  int get lengthInStages => wrappedRating.intData[_IntKeys.lengthInStages.index];
  set lengthInStages(int v) => wrappedRating.intData[_IntKeys.lengthInStages.index] = v;

  /// Calculate the current RD for this competitor based on the committed RD, volatility, and
  /// (fractional) number of pseudo-rating-periods since the last commit.
  ///
  /// If [upcomingVolatility] is provided, it will be used instead of the current volatility.
  /// If [asOfDate] is provided, it will be used instead of the current date.
  /// If [maximumRD] is provided, it will be used to limit the RD to the maximum value. It should
  /// be provided in internal units.
  ///
  /// No-argument calls are suitable for showing a real-time gain in RD in a UI. Both arguments
  /// should be provided when calculating the RD as part of the rating process.
  double calculateCurrentRD({double? upcomingVolatility, DateTime? asOfDate, double? maximumRD}) {
    asOfDate ??= DateTime.now();
    if(ratingPeriodLength == null) {
      var settings = wrappedRating.project.value!.settings.algorithm.settings as Glicko2Settings;
      ratingPeriodLength = settings.pseudoRatingPeriodLength;
    }
    if(asOfDate.isBefore(lastCommitTimestamp.toDateTime())) {
      return committedRD;
    }
    var volatilityValue = upcomingVolatility ?? this.volatility;
    var daysSinceLastCommit = asOfDate.difference(lastCommitTimestamp.toDateTime()).inDays;
    var ratingPeriodsSinceLastCommit = daysSinceLastCommit / ratingPeriodLength!;
    var rd = sqrt(pow(committedRD, 2) + (pow(volatilityValue, 2) * ratingPeriodsSinceLastCommit));
    if(maximumRD != null) {
      rd = min(rd, maximumRD);
    }
    return rd;
  }

  @override
  List<Glicko2RatingEvent> get combinedRatingEvents => []..addAll(ratingEvents)..addAll(emptyRatingEvents);

  @override
  List<Glicko2RatingEvent> get emptyRatingEvents => [];

  @override
  void updateTrends(List<RatingEvent> changes) {
    // ...
  }

  void updateFromEvents(List<RatingEvent> events) {
    super.updateFromEvents(events);
    for(var e in events) {
      e as Glicko2RatingEvent;
      lengthInStages += e.stages;

      wrappedRating.newRatingEvents.add(e.wrappedEvent);
      lastSeen = e.date;
      lastCommitTimestamp = e.date.millisecondsSinceEpoch ~/ 1000;
      currentRDTimestamp = e.date.millisecondsSinceEpoch ~/ 1000;

      committedRD += e.rdChange;
      currentRD = committedRD;
      volatility += e.volatilityChange;
      rating += e.ratingChange;
    }
  }

  @override
  Glicko2RatingEvent wrapEvent(DbRatingEvent e) {
    return Glicko2RatingEvent.wrap(e);
  }

  Glicko2Rating.wrapDbRating(DbShooterRating rating) : super.wrapDbRating(rating);

  Glicko2Rating.copy(Glicko2Rating other) : super.copy(other) {
    this.volatility = other.volatility;
    this.currentRD = other.currentRD;
    this.lastCommitTimestamp = other.lastCommitTimestamp;
    this.currentRDTimestamp = other.currentRDTimestamp;
    this.committedRD = other.committedRD;
  }
}
