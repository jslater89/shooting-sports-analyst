/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math';

import 'package:collection/collection.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_change.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/points/points_rating_change.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/points/points_settings.dart';
import 'package:shooting_sports_analyst/data/sorted_list.dart';
import 'package:shooting_sports_analyst/data/sport/model.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';

enum _DoubleKeys {
  participationBonus,
}
enum _IntKeys {
  matchesToCount,
}

class PointsRating extends ShooterRating {
  double get participationBonus => wrappedRating.doubleData[_DoubleKeys.participationBonus.index];
  set participationBonus(double v) => wrappedRating.doubleData[_DoubleKeys.participationBonus.index] = v;

  int get matchesToCount => wrappedRating.intData[_IntKeys.matchesToCount.index];
  set matchesToCount(int v) => wrappedRating.intData[_IntKeys.matchesToCount.index] = v;

  @override
  double get rating => wrappedRating.rating + participationBonus * length;

  List<RatingEvent> get ratingEvents {
    if(!wrappedRating.events.isLoaded) {
      wrappedRating.events.loadSync();
    }
    var events = <PointsRatingEvent>[];
    for(var e in wrappedRating.events) {
      events.add(PointsRatingEvent.wrap(e));
    }
    return events;
  }

  /// All events, sorted high to low
  late SortedList<PointsRatingEvent> events;

  @override
  void updateFromEvents(List<RatingEvent> events) {
    for(var event in events) {
      if(event.ratingChange.isNaN) {
        this.emptyRatingEvents.add(event);
      }
      else {
        this.events.add(event as PointsRatingEvent);
      }
    }

    wrappedRating.rating = usedEvents().map((e) => e.ratingChange).sum;

    if(this.events.isNotEmpty) {
      lastSeen = this.events
          .sorted((a, b) => b.match.date.compareTo(a.match.date))
          .first
          .match
          .date;
    }
  }

  @override
  DateTime get lastSeen => wrappedRating.lastSeen;
  @override
  set lastSeen(DateTime d) {
    if(d.isAfter(wrappedRating.lastSeen)) wrappedRating.lastSeen = d;
  }

  Classification? get lastClassification => wrappedRating.lastClassification;
  set lastClassification(Classification? c) {
    if(c == null) return;

    // only change a shooter's class if it's better than the last-seen class,
    // since points ratings may often combine several divisions
    var lastClass = wrappedRating.lastClassification;
    if(lastClass == null) lastClass = c;

    if(c.index < lastClass.index) {
      lastClass = c;
    }
  }

  List<RatingEvent> usedEvents() {
    int matchCount = wrappedRating.intData[_IntKeys.matchesToCount.index];
    if(matchCount == 0) matchCount = this.events.length;

    int window = min(this.events.length, matchCount);
    var usedEvents = this.events.sublist(0, window);
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
    this.events = SortedList(comparator: _ratingComparator);
    if(date.isAfter(lastSeen)) lastSeen = date;
    lastClassification = shooter.classification;
  }

  PointsRating.copy(PointsRating other) :
        this.events = SortedList.copy(other.events),
        super.copy(other);

  PointsRating.wrapDbRating(DbShooterRating rating) : super.wrapDbRating(rating) {
    this.events = SortedList(comparator: _ratingComparator);
    this.events.addAll(ratingEvents.cast<PointsRatingEvent>());
  }

  final int Function(PointsRatingEvent a, PointsRatingEvent b) _ratingComparator = (a, b) {
    return b.ratingChange.compareTo(a.ratingChange);
  };

  @override
  List<RatingEvent> get combinedRatingEvents => []..addAll(ratingEvents)..addAll(emptyRatingEvents);

  @override
  List<RatingEvent> emptyRatingEvents = [];
  
  @override
  void ratingEventsChanged() {
    // no-op
  }
}