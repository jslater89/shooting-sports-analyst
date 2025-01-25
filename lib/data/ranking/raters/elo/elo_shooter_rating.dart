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

class EloShooterRating extends ShooterRating {
  static late double errorScale;

  double get variance => wrappedRating.doubleData[_DoubleKeys.variance.index];
  set variance(double v) => wrappedRating.doubleData[_DoubleKeys.variance.index] = v;

  double get direction => wrappedRating.doubleData[_DoubleKeys.mediumDirection.index];
  set direction(double v) => wrappedRating.doubleData[_DoubleKeys.mediumDirection.index] = v;

  double get shortDirection => wrappedRating.doubleData[_DoubleKeys.shortDirection.index];
  set shortDirection(double v) => wrappedRating.doubleData[_DoubleKeys.shortDirection.index] = v;

  double get longDirection => wrappedRating.doubleData[_DoubleKeys.longDirection.index];
  set longDirection(double v) => wrappedRating.doubleData[_DoubleKeys.longDirection.index] = v;

  double directionWithWindow(int window, {List<RatingEvent>? preloadedEvents}) {
    if(wrappedRating.length == 0) return 0;

    late List<IRatingEvent> events;
    if(preloadedEvents != null) {
      events = preloadedEvents.getTailWindow(window);
    }
    else {
      events = wrappedRating.getEventsInWindowSync(window: window);
    }

    int total = events.length;
    int positive = events.where((element) => element.ratingChange >= 0).length;

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
    List<RatingEvent> events;
    if((window + offset) >= ratingEvents.length) {
      if(offset < (ratingEvents.length)) events = ratingEvents.sublist(0, ratingEvents.length - offset);
      else events = ratingEvents;
    }
    else {
      events = ratingEvents.sublist(ratingEvents.length - (window + offset), ratingEvents.length - offset);
    }

    return events;
  }

  double meanSquaredErrorWithWindow({int window = ShooterRating.baseTrendWindow, int offset = 0}) {
    // With default settings, this yields a starting normalized error of 400,
    // which more or less jives with observation.
    if(ratingEvents.isEmpty) return 0.5;

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
    if(errors.isEmpty) return 0.5;

    late List<double> ratingErrors;
    if((window + offset) >= errors.length) {
      if(offset < (errors.length)) ratingErrors = errors.sublist(0, errors.length - offset);
      else ratingErrors = errors;
    }
    else {
      ratingErrors = errors.sublist(errors.length - (window + offset), errors.length - offset);
    }

    double currentDecay = 1.0;
    double squaredSum = 0.0;
    double length = 0.0;
    var reversed = ratingErrors.reversed.toList();
    for(int i = 0; i < reversed.length; i++) {
      if(i >= fullEffect) {
        currentDecay *= decayAfterFull;
      }

      squaredSum += pow(reversed[i], 2) * currentDecay;
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

  double get averageRatingChangeError => averageRatingChangeErrorWithWindow();

  double get decayingAverageRatingChangeError => decayingAverageRatingChangeErrorWithWindow(window: (ShooterRating.baseTrendWindow * 1.5).round());

  double averageRatingChangeErrorWithWindow({int window = ShooterRating.baseTrendWindow, int offset = 0}) {
    if (ratingEvents.isEmpty) return 0.0;
    var events = eventsForWindow(window: window, offset: offset);
    return sqrt(events.map((e) => e.ratingChange * e.ratingChange).average);
  }

  double decayingAverageRatingChangeErrorWithWindow({
    int window = ShooterRating.baseTrendWindow * 2,
    int fullEffect = ShooterRating.baseTrendWindow,
    int offset = 0,
    double decayAfterFull = 0.9,
  }) {
    if (ratingEvents.isEmpty) return 0.0;
    var events = eventsForWindow(window: window, offset: offset);
    
    double currentDecay = 1.0;
    double weightedSum = 0.0;
    double totalWeight = 0.0;
    
    var reversed = events.reversed.toList();
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

  List<RatingEvent>? _ratingEvents = null;

  List<RatingEvent> get ratingEvents {
    if(_ratingEvents == null) {
      var events = AnalystDatabase().getRatingEventsForSync(wrappedRating);
      _ratingEvents = events.map((e) => EloRatingEvent.wrap(e)).toList();
    }

    List<EloRatingEvent> newRatingEvents = [];
    if(wrappedRating.newRatingEvents.isNotEmpty) {
      var unpersistedEvents = wrappedRating.newRatingEvents.map((e) => EloRatingEvent.wrap(e));
      newRatingEvents.addAll(unpersistedEvents);
    }

    var out = [..._ratingEvents!, ...newRatingEvents];
    return out;
  }

  List<double>? _errors = null;
  List<double> get errors {
    if(_errors == null) {
      var doubleData = AnalystDatabase().getRatingEventDoubleDataForSync(wrappedRating);
      _errors = doubleData.map((e) => EloRatingEvent.getErrorFromDoubleData(e)).toList();
    }

    List<double> newErrors = [];
    if(wrappedRating.newRatingEvents.isNotEmpty) {
      var unpersistedErrors = wrappedRating.newRatingEvents.map((e) => EloRatingEvent.getError(e));
      newErrors.addAll(unpersistedErrors);
    }

    return [..._errors!, ...newErrors];
  }

  List<RatingEvent> emptyRatingEvents = [];

  void clearRatingEventCache() {
    _ratingEvents = null;
  }

  void ratingEventsChanged() {
    clearRatingEventCache();
  }

  // TODO: combine this in more intelligent fashion, preserving order where possible
  // TODO: ... like with database queries, maybe
  List<RatingEvent> get combinedRatingEvents => []..addAll(ratingEvents)..addAll(emptyRatingEvents);

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
    var currentLength = ratingEvents.length;
    var longTrendWindow = min(currentLength, ShooterRating.baseTrendWindow * 2);
    var trendWindow = min(currentLength, ShooterRating.baseTrendWindow);

    if(longTrendWindow == 0) {
      return;
    }

    // TODO: get a double list of the longTrendWindow most recent historical rating changes
    // TODO: get a double list of the longTrendWindow most recent historical ratings
    // We only need the above TODOs, not the full rating events, which should
    // speed things up dramatically.
    var events = ratingEvents.sublist(ratingEvents.length - longTrendWindow);
    var stdDevEvents = events.getTailWindow(trendWindow);
    var stdDev = sqrt(stdDevEvents.map((e) => pow(e.ratingChange, 2)).sum / (stdDevEvents.length - 1));

    variance = stdDev;

    shortDirection = directionWithWindow(ShooterRating.baseTrendWindow ~/ 2, preloadedEvents: events);
    direction = directionWithWindow(ShooterRating.baseTrendWindow, preloadedEvents: events);
    longDirection = directionWithWindow(ShooterRating.baseTrendWindow * 2, preloadedEvents: events);

    shortTrend = rating - averageRating(window: ShooterRating.baseTrendWindow ~/ 2, preloadedEvents: events).firstRating;
    mediumTrend = rating - averageRating(window: ShooterRating.baseTrendWindow, preloadedEvents: events).firstRating;
    longTrend = rating - averageRating(window: ShooterRating.baseTrendWindow * 2, preloadedEvents: events).firstRating;

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
    clearRatingEventCache();
    wrappedRating.events.clear();
    wrappedRating.events.addAll(events.map((e) => e.wrappedEvent));
  }

  void copyRatingFrom(EloShooterRating other) {
    super.copyRatingFrom(other);
    this.rating = other.rating;
    this.variance = other.variance;
    this.replaceAllRatingEvents(other.ratingEvents.map((e) => EloRatingEvent.copy(e as EloRatingEvent)).toList());
  }

  EloShooterRating.copy(EloShooterRating other) :
        super.copy(other) {
    this.replaceAllRatingEvents(other.ratingEvents.map((e) => EloRatingEvent.copy(e as EloRatingEvent)).toList());
    this.variance = other.variance;
  }

  @override
  String toString() {
    return "${getName(suffixes: false)} $memberNumber ${rating.round()} ($hashCode)";
  }
}