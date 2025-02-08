/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math';

import 'package:collection/collection.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/match/rating_project_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/db_rating_event.dart';
// import 'package:shooting_sports_analyst/data/db/object/rating/elo/db_elo_rating.dart';
import 'package:shooting_sports_analyst/data/model.dart';
import 'package:shooting_sports_analyst/data/ranking/rater_types.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/elo/elo_rating_change.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/elo/multiplayer_percent_elo_rater.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/shooter.dart';
import 'package:shooting_sports_analyst/util.dart';

enum _DoubleKeys {
  variance,
  shortTrend,
  mediumTrend,
  longTrend,
  shortDirection,
  mediumDirection,
  longDirection
}

class EloShooterRating extends ShooterRating<EloRatingEvent> {
  static late double errorScale;

  double get variance => wrappedRating.doubleData[_DoubleKeys.variance.index];
  set variance(double v) => wrappedRating.doubleData[_DoubleKeys.variance.index] = v;

  double get direction => wrappedRating.doubleData[_DoubleKeys.mediumDirection.index];
  set direction(double v) => wrappedRating.doubleData[_DoubleKeys.mediumDirection.index] = v;

  double get shortDirection => wrappedRating.doubleData[_DoubleKeys.shortDirection.index];
  set shortDirection(double v) => wrappedRating.doubleData[_DoubleKeys.shortDirection.index] = v;

  double get longDirection => wrappedRating.doubleData[_DoubleKeys.longDirection.index];
  set longDirection(double v) => wrappedRating.doubleData[_DoubleKeys.longDirection.index] = v;

  double directionWithWindow(int window, {List<double>? preloadedChanges, bool checkLength = true}) {
    if(checkLength && (wrappedRating.length == 0)) return 0;

    late List<double> changes;
    if(preloadedChanges != null) {
      changes = preloadedChanges.getTailWindow(window);
      if(changes.length == 0) return 0;
    }
    else {
      // This is in order from newest to oldest, but we don't need to switch it because direction doesn't
      // care about the order of events.
      changes = AnalystDatabase().getRatingEventChangeForSync(wrappedRating, limit: window, offset: 0, order: Order.descending);
    }

    int total = changes.length;
    int positive = changes.where((element) => element >= 0).length;

    // Center around zero, expand to range [-1, 1]
    return ((positive / total) - 0.5) * 2.0;
  }

  double get shortTrend => wrappedRating.doubleData[_DoubleKeys.shortTrend.index];
  set shortTrend(double v) => wrappedRating.doubleData[_DoubleKeys.shortTrend.index] = v;

  double get mediumTrend => wrappedRating.doubleData[_DoubleKeys.mediumTrend.index];
  set mediumTrend(double v) => wrappedRating.doubleData[_DoubleKeys.mediumTrend.index] = v;

  double get longTrend => wrappedRating.doubleData[_DoubleKeys.longTrend.index];
  set longTrend(double v) => wrappedRating.doubleData[_DoubleKeys.longTrend.index] = v;

  // double get trend => (shortTrend + mediumTrend + longTrend) / 3;

  double get meanSquaredError {
    return meanSquaredErrorWithWindow(window: ratingEvents.length);
  }

  List<RatingEvent> eventsForWindow({int window = ShooterRating.baseTrendWindow, int offset = 0}) {
    return AnalystDatabase().getRatingEventsForSync(wrappedRating, limit: window, offset: offset).map((e) => wrapEvent(e)).toList();
  }

  double meanSquaredErrorWithWindow({int window = ShooterRating.baseTrendWindow, int offset = 0}) {
    // With default settings, this yields a starting normalized error of 400,
    // which more or less jives with observation.
    if(length == 0) return 0.5;

    var events = eventsForWindow(window: window, offset: offset);

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
    var dbWindow = window - wrappedRating.newRatingEvents.length;
    List<double> dbRatingErrors = AnalystDatabase().getRatingEventDoubleDataForSync(
      wrappedRating,
      limit: dbWindow,
      offset: offset,
      order: Order.descending,
      nonzeroChange: true,
    ).map((e) => EloRatingEvent.getErrorFromDoubleData(e)).toList();

    // Get a list of errors in order from newest to oldest, including any new errors.
    var newRatingErrors = wrappedRating.newRatingEvents.reversed.map((e) => EloRatingEvent.getError(e));
    List<double> ratingErrors = [...newRatingErrors, ...dbRatingErrors];

    double currentDecay = 1.0;
    double squaredSum = 0.0;
    double length = 0.0;
    for(int i = 0; i < ratingErrors.length; i++) {
      if(i >= fullEffect) {
        currentDecay *= decayAfterFull;
      }

      squaredSum += pow(ratingErrors[i], 2) * currentDecay;
      length += 1.0 * currentDecay;
    }
    return squaredSum / length;
  }

  double get normalizedError {
    return normalizedErrorWithWindow(window: length);
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

  double get averageRatingChangeError => averageRatingChangeErrorWithWindow();

  double get decayingAverageRatingChangeError => decayingAverageRatingChangeErrorWithWindow(window: (ShooterRating.baseTrendWindow * 1.5).round());

  double averageRatingChangeErrorWithWindow({int window = ShooterRating.baseTrendWindow, int offset = 0}) {
    if (length == 0) return 0.0;
    var events = eventsForWindow(window: window, offset: offset);
    return sqrt(events.map((e) => e.ratingChange * e.ratingChange).average);
  }

  double decayingAverageRatingChangeErrorWithWindow({
    int window = ShooterRating.baseTrendWindow * 2,
    int fullEffect = ShooterRating.baseTrendWindow,
    int offset = 0,
    double decayAfterFull = 0.9,
  }) {
    if (length == 0) return 0.0;
    var events = eventsForWindow(window: window, offset: offset);
    
    double currentDecay = 1.0;
    double weightedSum = 0.0;
    double totalWeight = 0.0;
    
    var reversed = events; // ordered desc from DB
    for (int i = 0; i < reversed.length; i++) {
      var e = reversed[i] as EloRatingEvent;
      if (i >= fullEffect) {
        currentDecay *= decayAfterFull;
      }
      
      weightedSum += pow(e.ratingChange, 2) * currentDecay;
      totalWeight += currentDecay;
    }
    
    return sqrt(weightedSum / totalWeight);
  }

  set standardError(double v) => wrappedRating.error = v;
  double get standardError => wrappedRating.error;

  double calculateStandardError() {
    return normalizedDecayingErrorWithWindow(
      window: (ShooterRating.baseTrendWindow * 1.5).round(),
      fullEffect: ShooterRating.baseTrendWindow,
    );
  }

  double standardErrorWithOffset({int offset = 0}) {
    return normalizedDecayingErrorWithWindow(
      window: (ShooterRating.baseTrendWindow * 1.5).round(),
      fullEffect: ShooterRating.baseTrendWindow,
      offset: offset,
    );
  }

  double get backRatingError {
    var events = eventsForWindow();
    var errors = events.map((e) => (e as EloRatingEvent).backRatingError);
    var average = errors.average;
    return average;
    // var variance = (errors.map((e) => pow(e - average, 2)).sum) / errors.length;
    // return sqrt(variance);
  }

  List<EloRatingEvent> emptyRatingEvents = [];

  // TODO: combine this in more intelligent fashion, preserving order where possible
  // TODO: ... like with database queries, maybe
  List<EloRatingEvent> get combinedRatingEvents => []..addAll(ratingEvents)..addAll(emptyRatingEvents);

  EloShooterRating(MatchEntry shooter, double initialRating, {required super.sport, required DateTime date}) :
      super(shooter,
        date: date,
        intDataElements: 0,
        doubleDataElements: _DoubleKeys.values.length,
      ) {
    this.wrappedRating.sportName = sportName;
    this.wrappedRating.firstName = firstName;
    this.wrappedRating.lastName = lastName;
    this.wrappedRating.memberNumber = memberNumber;
    this.wrappedRating.lastClassification = lastClassification;
    this.wrappedRating.division = division;
    this.wrappedRating.ageCategory = ageCategory;
    this.wrappedRating.female = female;
    this.wrappedRating.rating = initialRating;
    this.wrappedRating.error = 0.0;
    this.wrappedRating.rawConnectivity = 0.0;
    this.wrappedRating.connectivity = 0.0;
    this.wrappedRating.firstSeen = firstSeen;
    this.wrappedRating.lastSeen = lastSeen;
  }

  EloShooterRating.wrapDbRating(DbShooterRating rating) : super.wrapDbRating(rating);

  void updateFromEvents(List<RatingEvent> events) {
    for(var e in events) {
      e as EloRatingEvent;
      if(e.baseK != 0) {
        rating += e.ratingChange;
      }
      wrappedRating.newRatingEvents.add(e.wrappedEvent);
    }

    standardError = calculateStandardError();
  }

  void updateTrends(List<RatingEvent> changes) {
    // [changes] is not yet persisted, so we want a list of up to longTrendWindow events
    // that is [...dbEvents, ...changes].
    var longTrendWindow = ShooterRating.baseTrendWindow * 2;
    var trendWindow = ShooterRating.baseTrendWindow;

    var meaningfulChanges = changes.where((e) => e.ratingChange != 0.0).toList();

    var newEventContribution = meaningfulChanges.length;
    var dbRequirement = longTrendWindow - newEventContribution;

    if(longTrendWindow == 0) {
      return;
    }

    List<double> ratingChanges = [];
    List<double> ratingValues = [];

    if(dbRequirement > 0) {
      List<double> dbRatingChanges = AnalystDatabase().getRatingEventChangeForSync(wrappedRating, limit: dbRequirement, offset: 0, order: Order.descending, nonzeroChange: true);
      List<double> dbRatingValues = AnalystDatabase().getRatingEventRatingForSync(wrappedRating, limit: dbRequirement, offset: 0, order: Order.descending, nonzeroChange: true);

      // Put the list in order from oldest to newest.
      ratingChanges.addAll(dbRatingChanges.reversed);
      ratingValues.addAll(dbRatingValues.reversed);
    }

    ratingChanges.addAll(meaningfulChanges.map((e) => e.ratingChange));
    ratingValues.addAll(meaningfulChanges.map((e) => e.newRating));

    var stdDevChanges = ratingChanges.getTailWindow(trendWindow);
    var stdDev = sqrt(stdDevChanges.map((e) => pow(e, 2)).sum / (stdDevChanges.length - 1));

    variance = stdDev;

    shortDirection = directionWithWindow(ShooterRating.baseTrendWindow ~/ 2, preloadedChanges: ratingChanges, checkLength: false);
    direction = directionWithWindow(ShooterRating.baseTrendWindow, preloadedChanges: ratingChanges, checkLength: false);
    longDirection = directionWithWindow(ShooterRating.baseTrendWindow * 2, preloadedChanges: ratingChanges, checkLength: false);

    shortTrend = rating - averageRating(window: ShooterRating.baseTrendWindow ~/ 2, preloadedRatings: ratingValues).firstRating;
    mediumTrend = rating - averageRating(window: ShooterRating.baseTrendWindow, preloadedRatings: ratingValues).firstRating;
    longTrend = rating - averageRating(window: ShooterRating.baseTrendWindow * 2, preloadedRatings: ratingValues).firstRating;

    // if(Rater.processMemberNumber(shooter.memberNumber) == "128393") {
    //   debugPrint("Trends for ${shooter.lastName}");
    //   debugPrint("$totalVariance / $trendWindow = $variance");
    //   debugPrint("$totalTrend / $trendWindow = $trend");
    // }
  }

  /// Replaces all rating events with a new set of rating events.
  ///
  /// This is used in copy functions, and _does not_ save the link!
  /// The caller must persist it.
  void replaceAllRatingEvents(List<EloRatingEvent> events) {
    wrappedRating.events.clear();
    wrappedRating.events.addAll(events.map((e) => e.wrappedEvent));
    super.ratingEventsChanged();
  }

  void copyRatingFrom(EloShooterRating other) {
    super.copyRatingFrom(other);
    this.rating = other.rating;
    this.variance = other.variance;
    this.replaceAllRatingEvents(other.ratingEvents.map((e) => EloRatingEvent.copy(e)).toList());
  }

  EloShooterRating.copy(EloShooterRating other) :
        super.copy(other) {
    this.replaceAllRatingEvents(other.ratingEvents.map((e) => EloRatingEvent.copy(e)).toList());
    this.variance = other.variance;
  }

  @override
  String toString() {
    return "${getName(suffixes: false)} $memberNumber ${rating.round()} ($hashCode)";
  }

  @override
  EloRatingEvent wrapEvent(DbRatingEvent e) {
    return EloRatingEvent.wrap(e);
  }
}