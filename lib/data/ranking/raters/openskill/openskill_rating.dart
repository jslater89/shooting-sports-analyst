/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */


import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/ranking/rater_types.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/openskill/openskill_rating_change.dart';

class OpenskillRating extends ShooterRating {
  @override
  double get rating => ordinal;

  double mu;
  double sigma;

  double get ordinal => mu - 2*sigma;

  @override
  List<RatingEvent> ratingEvents = [];

  OpenskillRating(Shooter shooter, this.mu, this.sigma, {DateTime? date}) :
      super(shooter, date: date);

  OpenskillRating.copy(OpenskillRating other) :
      this.mu = other.mu,
      this.sigma = other.sigma,
      this.ratingEvents = other.ratingEvents.map((e) => OpenskillRatingEvent.copy(e as OpenskillRatingEvent)).toList(),
      super.copy(other);

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
  List<RatingEvent> emptyRatingEvents = [];
}