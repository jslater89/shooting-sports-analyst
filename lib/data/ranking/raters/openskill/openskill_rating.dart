/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */


import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/match/rating_project_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/db_rating_event.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/rater_types.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/openskill/openskill_rating_change.dart';
import 'package:shooting_sports_analyst/data/sport/model.dart';

enum _DoubleKeys {
  mu,
  sigma,
}

class OpenskillRating extends ShooterRating<OpenskillRatingEvent> {
  @override
  double get rating => ordinal;

  double get mu => wrappedRating.doubleData[_DoubleKeys.mu.index];
  set mu(double v) => wrappedRating.doubleData[_DoubleKeys.mu.index] = v;

  double get sigma => wrappedRating.error;
  set sigma(double v) => wrappedRating.error = v;

  double get ordinal => mu - 2*sigma;

  double sigmaWithOffset(int offset) {
    List<double> dbRatingErrors = AnalystDatabase().getRatingEventDoubleDataForSync(
      wrappedRating,
      limit: 1,
      offset: offset,
      order: Order.descending,
      nonzeroChange: true,
    ).map((e) => OpenskillRatingEvent.getSigmaFromDoubleData(e)).toList();

    return dbRatingErrors.firstOrNull ?? 0.0;
  }

  OpenskillRating(MatchEntry shooter, double mu, double sigma, {required super.sport, required DateTime date}) :
      super(shooter, date: date, doubleDataElements: 2, intDataElements: 0) {
    this.mu = mu;
    this.sigma = sigma;
    this.wrappedRating.sportName = sportName;
    this.wrappedRating.firstName = firstName;
    this.wrappedRating.lastName = lastName;
    this.wrappedRating.memberNumber = memberNumber;
    this.wrappedRating.lastClassification = lastClassification;
    this.wrappedRating.division = division;
    this.wrappedRating.ageCategory = ageCategory;
    this.wrappedRating.female = female;
    this.wrappedRating.rating = 0.0;
    this.wrappedRating.rawConnectivity = 0.0;
    this.wrappedRating.connectivity = 0.0;
    this.wrappedRating.firstSeen = firstSeen;
    this.wrappedRating.lastSeen = lastSeen;
  }

  OpenskillRating.copy(OpenskillRating other) :
      super.copy(other) {
    this.replaceAllRatingEvents(other.ratingEvents.map((e) => OpenskillRatingEvent.copy(e)).toList());
    this.mu = other.mu;
    this.sigma = other.sigma;
  }

  OpenskillRating.wrapDbRating(DbShooterRating rating) : super.wrapDbRating(rating);

  @override
  void updateFromEvents(List<RatingEvent> events) {
    for(var event in events) {
      event as OpenskillRatingEvent;
      wrappedRating.newRatingEvents.add(event.wrappedEvent);

      mu += event.muChange;
      sigma += event.sigmaChange;
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
  List<OpenskillRatingEvent> get combinedRatingEvents => []..addAll(ratingEvents)..addAll(emptyRatingEvents);

  @override
  OpenskillRatingEvent wrapEvent(DbRatingEvent e) {
    return OpenskillRatingEvent.wrap(e);
  }
  
  @override
  List<OpenskillRatingEvent> get emptyRatingEvents => [];
}