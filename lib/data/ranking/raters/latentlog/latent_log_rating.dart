/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math';

import 'package:shooting_sports_analyst/data/database/schema/ratings/db_rating_event.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_change.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/latentlog/latent_log_rater.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/latentlog/latent_log_rating_event.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/latentlog/latent_log_settings.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/shooter.dart';
import 'package:shooting_sports_analyst/util.dart';


enum _DoubleKeys {
  // rating and variance are stored in wrappedRating.rating and wrappedRating.error

  /// The dispersion parameter for this competitor.
  dispersion,

  /// The current variance for this competitor, accounting for time since the last update.
  currentVariance,

  /// The momentum parameter for this competitor.
  momentum,
}

enum _IntKeys {
  /// Seconds since Unix epoch for the commit time of last rating update, i.e., the
  /// timestamp of the last match.
  lastCommitTimestamp,
  /// Seconds since Unix epoch for the timestamp of the current variance calculation. If
  /// the current variance is requested and the year-month-day in this timestamp is the same
  /// as the current timestamp, the cached current variance can be returned directly.
  currentVarianceTimestamp,
  /// The number of stages shot.
  lengthInStages,
}

class LatentLogRating extends ShooterRating<LatentLogRatingEvent> {
  static const ratingPeriodLengthInDays = 365;

  LatentLogRating(MatchEntry shooter, {
    required this.settings,
    required super.sport,
    required super.date,
    required double initialRating,
    required double initialVariance,
    required double initialDispersion,

  }) : super(
    shooter,
    intDataElements: _IntKeys.values.length,
    doubleDataElements: _DoubleKeys.values.length,
  ) {
    this.rating = initialRating;
    this.variance = initialVariance;
    this.dispersion = initialDispersion;
    this.momentum = 0.0;
  }

  LatentLogSettings settings;

  double get trend => momentum;
  double get scaledRating => displayRating;
  double get scaledAgedRating => displayAgedRating;
  String get formattedRating => formatNumericRating(rating);
  String get formattedAgedRating => formatNumericRating(ratingToday);

  String formatNumericRating(double rating) {
    return settings.formatNumericRating(rating);
  }

  String formatNumericRatingChange(double ratingChange) {
    return settings.formatNumericRating(ratingChange);
  }

  DateTime? _cachedAgedRatingDate;
  double? _cachedAgedRating;
  double calculateAgedRating({DateTime? asOfDate}) {
    asOfDate ??= DateTime.now();
    if(_cachedAgedRating != null && _cachedAgedRatingDate != null && _cachedAgedRatingDate!.isSameDay(asOfDate)) {
      return _cachedAgedRating!;
    }

    _cachedAgedRatingDate = asOfDate;
    if(lastCommitTimestamp == 0 || asOfDate.isBefore(lastCommitTimestamp.toDateTime())) {
      _cachedAgedRating = rating;
      return rating;
    }
    final daysSinceLastCommit = asOfDate.difference(lastCommitTimestamp.toDateTime()).inDays;
    final yearsSinceLastCommit = daysSinceLastCommit / 365.0;
    final effectiveYearsSinceLastCommit = max(0, yearsSinceLastCommit - settings.meanReversionGraceYears);

    final deviationFromCenter = rating - settings.startingRating;
    _cachedAgedRating =
        settings.startingRating +
        deviationFromCenter *
            exp(-settings.meanReversionDecayRate * effectiveYearsSinceLastCommit);
    return _cachedAgedRating!;
  }

  double get ratingToday {
    return calculateAgedRating(asOfDate: DateTime.now());
  }

  double get displayRating => rating * settings.scaleFactor + settings.scaleOffset;
  double get displayAgedRating => ratingToday * settings.scaleFactor + settings.scaleOffset;
  double get displayVariance => variance * settings.scaleFactor * settings.scaleFactor;
  double get displayCurrentVariance => varianceToday * settings.scaleFactor * settings.scaleFactor;
  double get displayDispersion => dispersion * settings.scaleFactor * settings.scaleFactor;
  double get displayMomentum => momentum * settings.scaleFactor;

  double get currentStandardDeviation => sqrt(varianceToday);
  double get displayStandardDeviation => sqrt(displayVariance);
  double get displayCurrentStandardDeviation => sqrt(displayCurrentVariance);
  double get displayDispersionStandardDeviation => sqrt(displayDispersion);

  double get variance => wrappedRating.error;
  set variance(double v) => wrappedRating.error = v;

  double get dispersion => wrappedRating.doubleData[_DoubleKeys.dispersion.index];
  set dispersion(double v) => wrappedRating.doubleData[_DoubleKeys.dispersion.index] = v;

  double get momentum => wrappedRating.doubleData[_DoubleKeys.momentum.index];
  set momentum(double v) => wrappedRating.doubleData[_DoubleKeys.momentum.index] = v;

  double get varianceToday {
    if(varianceTodayTimestamp.isSameDay(DateTime.now())) {
      return wrappedRating.doubleData[_DoubleKeys.currentVariance.index];
    }
    else {
      final updated = calculateCurrentVariance();
      wrappedRating.doubleData[_DoubleKeys.currentVariance.index] = updated;
      varianceTodayTimestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      return updated;
    }
  }
  set varianceToday(double v) => wrappedRating.doubleData[_DoubleKeys.currentVariance.index] = v;

  int get varianceTodayTimestamp => wrappedRating.intData[_IntKeys.currentVarianceTimestamp.index];
  set varianceTodayTimestamp(int v) => wrappedRating.intData[_IntKeys.currentVarianceTimestamp.index] = v;

  int get lastCommitTimestamp => wrappedRating.intData[_IntKeys.lastCommitTimestamp.index];
  set lastCommitTimestamp(int v) => wrappedRating.intData[_IntKeys.lastCommitTimestamp.index] = v;

  int get lengthInMatches => wrappedRating.length;

  int get lengthInStages => wrappedRating.intData[_IntKeys.lengthInStages.index];
  set lengthInStages(int v) => wrappedRating.intData[_IntKeys.lengthInStages.index] = v;

  static int getLengthInStages(DbShooterRating rating) {
    return rating.intData[_IntKeys.lengthInStages.index];
  }

  /// Calculate the current variance for this competitor.
  ///
  /// Variance is a simple function of time since last update and skill drift rate.
  double calculateCurrentVariance({DateTime? asOfDate}) {
    asOfDate ??= DateTime.now();
    if(lastCommitTimestamp == 0 || asOfDate.isBefore(lastCommitTimestamp.toDateTime())) {
      return variance;
    }
    var daysSinceLastCommit = asOfDate.difference(lastCommitTimestamp.toDateTime()).inDays;
    var ratingPeriodsSinceLastCommit = daysSinceLastCommit / ratingPeriodLengthInDays;
    var newVariance = variance + settings.skillDriftRate * ratingPeriodsSinceLastCommit;
    return min(settings.maximumVariance, newVariance);
  }

  @override
  int? get stageCount => lengthInStages;

  @override
  int? get matchCount => length;

  @override
  // TODO: implement combinedRatingEvents
  List<LatentLogRatingEvent> get combinedRatingEvents => throw UnimplementedError();

  @override
  // TODO: implement emptyRatingEvents
  List<LatentLogRatingEvent> get emptyRatingEvents => throw UnimplementedError();

  @override
  void updateTrends(List<RatingEvent> changes) {
    // ... no trends yet
  }

  void updateFromEvents(List<RatingEvent> events) {
    super.updateFromEvents(events);
    for(var e in events) {
      e as LatentLogRatingEvent;
      rating += e.ratingChange;
      variance += e.varianceChange;
      dispersion += e.dispersionChange;
      momentum += e.momentumChange;
      lengthInStages += e.stages;
      wrappedRating.newRatingEvents.add(e.wrappedEvent);
      lastCommitTimestamp = e.date.millisecondsSinceEpoch ~/ 1000;
    }
  }

  @override
  LatentLogRatingEvent wrapEvent(DbRatingEvent e) {
    return LatentLogRatingEvent.wrap(e, settings: settings);
  }

  LatentLogRating.wrapDbRatingWithSettings(LatentLogRater rater, DbShooterRating rating) :
    this.settings = rater.settings, super.wrapDbRating(rating);

  LatentLogRating.wrapDbRating(DbShooterRating rating) : this.settings = LatentLogSettings(), super.wrapDbRating(rating) {
    throw Exception("Must use wrapDbRatingWithSettings for LatentLogRating");
  }

  LatentLogRating.copy(LatentLogRating other) : this.settings = other.settings, super.copy(other) {
    this.momentum = other.momentum;
    this.dispersion = other.dispersion;
    this.varianceToday = other.varianceToday;
    this.lastCommitTimestamp = other.lastCommitTimestamp;
    this.varianceTodayTimestamp = other.varianceTodayTimestamp;
    this.lengthInStages = other.lengthInStages;
  }

  @override
  String toString() {
    return "$name $memberNumber ${displayRating.round()}/${variance.toStringAsFixed(2)}/${dispersion.toStringAsFixed(2)} ($hashCode)";
  }
}