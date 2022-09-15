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

  double bestRating(PointsSettings settings) {
    if(settings.matchesToCount == 0) return rating;

    if(settings.matchesToCount < 0) throw UnimplementedError();

    var usedRatings = usedEvents(settings);
    return usedRatings.map((e) => e.ratingChange).sum;
  }

  List<RatingEvent> usedEvents(PointsSettings settings) {
    var eventsByChange = ratingEvents.sorted((a, b) => b.ratingChange.compareTo(a.ratingChange));
    var usedRatings = eventsByChange.sublist(0, settings.matchesToCount);
    return usedRatings;
  }

  @override
  void updateTrends(List<RatingEvent> changes) {
    // TODO: implement updateTrends
  }

  PointsRating(Shooter shooter, {DateTime? date}) : this.rating = 0, super(shooter, date: date);

  PointsRating.copy(PointsRating other) : this.rating = other.rating, super.copy(other);
}