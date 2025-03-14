/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math';

import 'package:collection/collection.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/db_rating_event.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_change.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/points/points_rating_change.dart';
import 'package:shooting_sports_analyst/data/sorted_list.dart';
import 'package:shooting_sports_analyst/data/sport/model.dart';
import 'package:shooting_sports_analyst/util.dart';

enum _DoubleKeys {
  participationBonus,
}
enum _IntKeys {
  matchesToCount,
}

class PointsRating extends ShooterRating<PointsRatingEvent> {
  double get participationBonus => wrappedRating.doubleData[_DoubleKeys.participationBonus.index];
  set participationBonus(double v) => wrappedRating.doubleData[_DoubleKeys.participationBonus.index] = v;

  int get matchesToCount => wrappedRating.intData[_IntKeys.matchesToCount.index];
  set matchesToCount(int v) => wrappedRating.intData[_IntKeys.matchesToCount.index] = v;

  double get ratingFromScores => wrappedRating.rating;
  double get ratingFromParticipation => participationBonus * length;

  @override
  double get rating => ratingFromScores + ratingFromParticipation;

  List<PointsRatingEvent>? _cachedSortedEvents;
  /// All events, sorted high to low
  List<PointsRatingEvent> get sortedEvents {
    if(_cachedSortedEvents == null) {
      var events = ratingEvents;
      events.sort((a, b) => b.ratingChange.compareTo(a.ratingChange));
      _cachedSortedEvents = events;
    }
    return _cachedSortedEvents!;
  }


  @override
  void updateFromEvents(List<RatingEvent> events) {
    super.updateFromEvents(events);
    _cachedSortedEvents = null;
    for(var event in events) {
      wrappedRating.newRatingEvents.add(event.wrappedEvent);
    }

    wrappedRating.rating = usedEvents().map((e) => e.ratingChange).sum;

    if(this.ratingEvents.isNotEmpty) {
      lastSeen = this.ratingEvents
          .sorted((a, b) => b.match.date.compareTo(a.match.date))
          .first
          .match
          .date;
    }
  }

  List<RatingEvent> usedEvents() {
    int matchCount = wrappedRating.intData[_IntKeys.matchesToCount.index];
    if(matchCount == 0) matchCount = this.sortedEvents.length;
    var usedEvents = this.sortedEvents.getWindow(matchCount);
    return usedEvents;
  }

  @override
  void updateTrends(List<RatingEvent> changes) {}

  PointsRating(
    MatchEntry shooter,
    {
      required super.sport,
      required double participationBonus,
      required int matchesToCount,
      required DateTime date
    }) : super(
      shooter,
      date: date,
      intDataElements: _IntKeys.values.length,
      doubleDataElements: _DoubleKeys.values.length,
  ) {
    this.participationBonus = participationBonus;
    this.matchesToCount = matchesToCount;
    if(date.isAfter(lastSeen)) lastSeen = date;
    this.lastClassification = shooter.classification;
    this.wrappedRating.sportName = sportName;
    this.wrappedRating.firstName = firstName;
    this.wrappedRating.lastName = lastName;
    this.wrappedRating.memberNumber = memberNumber;
    this.wrappedRating.lastClassification = lastClassification;
    this.wrappedRating.division = division;
    this.wrappedRating.ageCategory = ageCategory;
    this.wrappedRating.female = female;
    this.wrappedRating.rating = 0.0;
    this.wrappedRating.error = 0.0;
    this.wrappedRating.rawConnectivity = 0.0;
    this.wrappedRating.connectivity = 0.0;
    this.wrappedRating.firstSeen = firstSeen;
    this.wrappedRating.lastSeen = lastSeen;
  }

  PointsRating.copy(PointsRating other) :
      super.copy(other) {
    this.replaceAllRatingEvents(other.ratingEvents.map((e) => PointsRatingEvent.copy(e)).toList());
  }

  PointsRating.wrapDbRating(DbShooterRating rating) : super.wrapDbRating(rating);


  final int Function(PointsRatingEvent a, PointsRatingEvent b) _ratingComparator = (a, b) {
    return b.ratingChange.compareTo(a.ratingChange);
  };

  @override
  PointsRatingEvent wrapEvent(DbRatingEvent e) {
    return PointsRatingEvent.wrap(e);
  }


  List<PointsRatingEvent> emptyRatingEvents = [];

  // TODO: combine this in more intelligent fashion, preserving order where possible
  // TODO: ... like with database queries, maybe
  List<PointsRatingEvent> get combinedRatingEvents => []..addAll(ratingEvents)..addAll(emptyRatingEvents);

  @override
  String toString() {
    return "PointsRating($name, scores: ${ratingFromScores.toStringAsFixed(1)}, participation: ${ratingFromParticipation.toStringAsFixed(1)})";
  }
}
