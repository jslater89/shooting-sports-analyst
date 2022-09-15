import 'dart:math';

import 'package:collection/collection.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/ranking/model/rating_change.dart';
import 'package:uspsa_result_viewer/data/ranking/model/shooter_rating.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/points/points_settings.dart';

class PointsRating extends ShooterRating<PointsRating> {
  @override
  double rating;

  @override
  List<RatingEvent> ratingEvents = [];

  @override
  void updateFromEvents(List<RatingEvent> events) {
    ratingEvents.addAll(events);
    for(var e in events) {
      rating += e.ratingChange;
    }
  }

  double bestRating(PointsSettings settings, double participationBonus) {
    if(settings.matchesToCount == 0) return rating;
    if(settings.matchesToCount < 0) throw UnimplementedError();

    var usedRatings = usedEvents(settings);
    rating = usedRatings.map((e) => e.ratingChange).sum + participationBonus * length;
    return rating;
  }

  List<RatingEvent> usedEvents(PointsSettings settings) {
    var lastIndex = min(settings.matchesToCount, ratingEvents.length);
    var eventsByChange = ratingEvents.sorted((a, b) => b.ratingChange.compareTo(a.ratingChange));
    var usedRatings = eventsByChange.sublist(0, lastIndex);
    return usedRatings;
  }

  @override
  void updateTrends(List<RatingEvent> changes) {}

  PointsRating(Shooter shooter, {DateTime? date}) : this.rating = 0, super(shooter, date: date);

  PointsRating.copy(PointsRating other) : this.rating = other.rating, super.copy(other);
}