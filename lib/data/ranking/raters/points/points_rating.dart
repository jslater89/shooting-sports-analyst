/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math';

import 'package:collection/collection.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_change.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/points/points_rating_change.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/points/points_settings.dart';
import 'package:shooting_sports_analyst/data/sorted_list.dart';
import 'package:shooting_sports_analyst/data/sport/model.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';

class PointsRating extends ShooterRating {
  final PointsSettings settings;
  final double participationBonus;

  @override
  double get rating => _rating + participationBonus * length;

  double _rating = 0.0;

  /// All events, in order of arrival
  List<PointsRatingEvent> temporalEvents = [];

  @override
  /// The N best events.
  List<RatingEvent> get ratingEvents => []..addAll(temporalEvents);

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
        this.temporalEvents.add(event);
      }
    }

    _rating = usedEvents().map((e) => e.ratingChange).sum;

    if(this.events.isNotEmpty) {
      _lastSeen = this.events
          .sorted((a, b) => b.match.date!.compareTo(a.match.date!))
          .first
          .match
          .date!;
    }
  }

  DateTime _lastSeen = DateTime(0);

  @override
  DateTime get lastSeen => _lastSeen;
  @override
  set lastSeen(DateTime d) {
    if(d.isAfter(_lastSeen)) _lastSeen = d;
  }

  Classification? _lastClass;
  Classification? get lastClassification => _lastClass;
  set lastClassification(Classification? c) {
    if(c == null) return;
    if(_lastClass == null) _lastClass = c;

    if(c.index < _lastClass!.index) {
      _lastClass = c;
    }
  }

  List<RatingEvent> usedEvents() {
    int matchCount = settings.matchesToCount;
    if(matchCount == 0) matchCount = this.events.length;

    int window = min(this.events.length, matchCount);
    var usedEvents = this.events.sublist(0, window);
    return usedEvents;
  }

  @override
  void updateTrends(List<RatingEvent> changes) {}

  PointsRating(
    Sport sport,
    MatchEntry shooter,
    this.settings,
    {required this.participationBonus, DateTime? date}) : super(shooter, date: date, sport: sport)
  {
    this.events = SortedList(comparator: _ratingComparator);
    if(date?.isAfter(_lastSeen) ?? false) _lastSeen = date!;
    _lastClass = shooter.classification;
  }

  PointsRating.copy(PointsRating other) :
        this._rating = other._rating,
        this.events = SortedList.copy(other.events),
        this.settings = other.settings,
        this.participationBonus = other.participationBonus,
        this._lastSeen = other._lastSeen,
        this._lastClass = other._lastClass,
        this.temporalEvents = other.temporalEvents,
        super.copy(other);

  final int Function(PointsRatingEvent a, PointsRatingEvent b) _ratingComparator = (a, b) {
    return b.ratingChange.compareTo(a.ratingChange);
  };

  @override
  List<RatingEvent> get combinedRatingEvents => []..addAll(ratingEvents)..addAll(emptyRatingEvents);

  @override
  List<RatingEvent> emptyRatingEvents = [];
}