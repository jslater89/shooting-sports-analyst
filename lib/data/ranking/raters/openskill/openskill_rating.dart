/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */


import 'package:shooting_sports_analyst/data/database/schema/ratings/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/rater_types.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/openskill/openskill_rating_change.dart';
import 'package:shooting_sports_analyst/data/sport/model.dart';

enum _DoubleKeys {
  mu,
  sigma,
}

class OpenskillRating extends ShooterRating {
  @override
  double get rating => ordinal;

  double get mu => wrappedRating.doubleData[_DoubleKeys.mu.index];
  set mu(double v) => wrappedRating.doubleData[_DoubleKeys.mu.index] = v;

  double get sigma => wrappedRating.doubleData[_DoubleKeys.sigma.index];
  set sigma(double v) => wrappedRating.doubleData[_DoubleKeys.sigma.index] = v;

  double get ordinal => mu - 2*sigma;

  List<RatingEvent> get ratingEvents {
    if(!wrappedRating.events.isLoaded) {
      wrappedRating.events.loadSync();
    }
    var events = <OpenskillRatingEvent>[];
    for(var e in wrappedRating.events) {
      events.add(OpenskillRatingEvent.wrap(e));
    }
    return events;
  }
  List<RatingEvent> emptyRatingEvents = [];

  OpenskillRating(MatchEntry shooter, double mu, double sigma, {required super.sport, required DateTime date}) :
      super(shooter, date: date, doubleDataElements: 2, intDataElements: 0) {
    this.mu = mu;
    this.sigma = sigma;
  }

  void replaceAllRatingEvents(List<OpenskillRatingEvent> events) {
    wrappedRating.events.clear();
    wrappedRating.events.addAll(events.map((e) => e.wrappedEvent));
  }

  OpenskillRating.copy(OpenskillRating other) :
      super.copy(other) {
    {
      this.replaceAllRatingEvents(other.ratingEvents.map((e) => OpenskillRatingEvent.copy(e as OpenskillRatingEvent)).toList());
      this.mu = mu;
      this.sigma = sigma;
    }
  }

  OpenskillRating.wrapDbRating(DbShooterRating rating) : super.wrapDbRating(rating);

  @override
  void updateFromEvents(List<RatingEvent> events) {
    for(var event in events) {
      event as OpenskillRatingEvent;

      if(event.muChange == 0 && event.sigmaChange == 0) {
        emptyRatingEvents.add(event);
      }
      else {
        mu += event.muChange;
        sigma += event.sigmaChange;
        ratingEvents.add(event);
      }
    }
  }

  @override
  void updateTrends(List<RatingEvent> changes) {
    // TODO: implement updateTrends
  }

  @override
  void copyRatingFrom(OpenskillRating other) {
    super.copyRatingFrom(other);
    mu = other.mu;
    sigma = other.sigma;
  }

  @override
  String toString() {
    return "${getName(suffixes: false)} ${rating.round()} ($hashCode)";
  }

  @override
  List<RatingEvent> get combinedRatingEvents => []..addAll(ratingEvents)..addAll(emptyRatingEvents);
  
  @override
  void ratingEventsChanged() {
    // no-op
  }
}