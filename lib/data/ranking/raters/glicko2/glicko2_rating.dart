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
import 'package:shooting_sports_analyst/data/ranking/raters/glicko2/glicko2_rater.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/glicko2/glicko2_rating_event.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/glicko2/glicko2_settings.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/shooter.dart';
import 'package:shooting_sports_analyst/util.dart';

enum _DoubleKeys {
  // rating and rating deviation are stored in wrappedRating.rating and wrappedRating.error
  /// The volatility parameter for this competitor.
  volatility,
  /// The current RD for this competitor, calculated on demand based on the difference between
  /// the current time and the last commit, in internal units.
  currentRD,
  /// The committed RD for this competitor, in internal units.
  committedRD,
  /// The current rating for this competitor, in internal units.
  rating,
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

/// Create a new Glicko-2 rating for a competitor. [initialRating] and [initialRD] should be in
/// display units.
class Glicko2Rating extends ShooterRating<Glicko2RatingEvent> {
  static int? ratingPeriodLength;
  Glicko2Settings settings;
  Glicko2Rating(MatchEntry shooter, {
    required this.settings,
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
    this.internalRating = settings.scaleToInternal(initialRating, offset: settings.initialRating);
    this.volatility = initialVolatility;
    this.currentInternalRD = settings.scaleToInternal(initialRD);
    this.committedInternalRD = settings.scaleToInternal(initialRD);
    this.lastCommitTimestamp = super.firstSeen.millisecondsSinceEpoch ~/ 1000;
    this.currentRDTimestamp = super.firstSeen.millisecondsSinceEpoch ~/ 1000;
  }

  double get volatility => wrappedRating.doubleData[_DoubleKeys.volatility.index];
  set volatility(double v) => wrappedRating.doubleData[_DoubleKeys.volatility.index] = v;

  /// This getter is current as of the current clock time.
  double get currentInternalRD {
    if(currentRDTimestamp.isSameDay(DateTime.now())) {
      return wrappedRating.doubleData[_DoubleKeys.currentRD.index];
    }
    else {
      final updated = calculateCurrentInternalRD();
      wrappedRating.doubleData[_DoubleKeys.currentRD.index] = updated;
      currentRDTimestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      return updated;
    }
  }
  set currentInternalRD(double v) => wrappedRating.doubleData[_DoubleKeys.currentRD.index] = v;

  // Get the currentRD for the current clock time in display units.
  double get currentDisplayRD => currentInternalRD * settings.scalingFactor;

  /// For Glicko-2, the rating getter and setter use display units, and the internalRating getter and setter use internal units.
  double get internalRating => wrappedRating.doubleData[_DoubleKeys.rating.index];
  set internalRating(double v) => wrappedRating.doubleData[_DoubleKeys.rating.index] = v;

  int get lastCommitTimestamp => wrappedRating.intData[_IntKeys.lastCommitTimestamp.index];
  set lastCommitTimestamp(int v) => wrappedRating.intData[_IntKeys.lastCommitTimestamp.index] = v;

  int get currentRDTimestamp => wrappedRating.intData[_IntKeys.currentRDTimestamp.index];
  set currentRDTimestamp(int v) => wrappedRating.intData[_IntKeys.currentRDTimestamp.index] = v;

  /// The RD that was calculated at the end of the last rating event commit, in display units.
  double get committedRD => wrappedRating.doubleData[_DoubleKeys.committedRD.index] * settings.scalingFactor;

  /// The RD that was calculated at the end of the last rating event commit, in internal units.
  double get committedInternalRD => wrappedRating.doubleData[_DoubleKeys.committedRD.index];
  set committedInternalRD(double v) => wrappedRating.doubleData[_DoubleKeys.committedRD.index] = v;

  /// The number of matches shot.
  int get lengthInMatches => wrappedRating.length;

  /// The number of stages shot.
  int get lengthInStages => wrappedRating.intData[_IntKeys.lengthInStages.index];
  set lengthInStages(int v) => wrappedRating.intData[_IntKeys.lengthInStages.index] = v;

  /// Calculate the current RD for this competitor based on the committed RD, volatility, and
  /// (fractional) number of pseudo-rating-periods since the last commit, in internal units.
  ///
  /// If [volatilityOverride] is provided, it will be used instead of the current volatility.
  /// If [asOfDate] is provided, it will be used instead of the current date.
  ///
  /// No-argument calls are suitable for showing a real-time gain in RD in a UI. Both arguments
  /// should be provided when calculating the RD as part of the rating process.
  double calculateCurrentInternalRD({double? volatilityOverride, DateTime? asOfDate}) {
    asOfDate ??= DateTime.now();
    if(ratingPeriodLength == null) {
      var settings = wrappedRating.project.value!.settings.algorithm.settings as Glicko2Settings;
      ratingPeriodLength = settings.pseudoRatingPeriodLength;
    }
    if(asOfDate.isBefore(lastCommitTimestamp.toDateTime())) {
      return committedInternalRD;
    }
    var volatilityValue = volatilityOverride ?? this.volatility;
    var daysSinceLastCommit = asOfDate.difference(lastCommitTimestamp.toDateTime()).inDays;
    var ratingPeriodsSinceLastCommit = daysSinceLastCommit / ratingPeriodLength!;
    var rd = sqrt(pow(committedInternalRD, 2) + (pow(volatilityValue, 2) * ratingPeriodsSinceLastCommit));
    rd = min(rd, settings.internalMaximumRD);
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

      committedInternalRD += e.rdChange;
      currentInternalRD = committedInternalRD;
      volatility += e.volatilityChange;
      internalRating += e.internalRatingChange;

      // Update display values
      rating = internalRating * settings.scalingFactor + settings.initialRating;
    }
  }

  @override
  Glicko2RatingEvent wrapEvent(DbRatingEvent e) {
    return Glicko2RatingEvent.wrap(e, settings: settings);
  }

  Glicko2Rating.wrapDbRatingWithSettings(Glicko2Rater rater, DbShooterRating rating) :
    this.settings = rater.settings, super.wrapDbRating(rating);

  Glicko2Rating.wrapDbRating(DbShooterRating rating) : this.settings = Glicko2Settings(), super.wrapDbRating(rating) {
    throw Exception("Must use wrapDbRatingWithSettings for Glicko2Rating");
  }

  Glicko2Rating.copy(Glicko2Rating other) : this.settings = other.settings, super.copy(other) {
    this.volatility = other.volatility;
    this.currentInternalRD = other.currentInternalRD;
    this.lastCommitTimestamp = other.lastCommitTimestamp;
    this.currentRDTimestamp = other.currentRDTimestamp;
    this.committedInternalRD = other.committedInternalRD;
  }

  @override
  String toString() {
    return "$name $memberNumber ${rating.round()}/${committedRD.round()}/${volatility.toStringAsFixed(4)} ($hashCode)";
  }
}
