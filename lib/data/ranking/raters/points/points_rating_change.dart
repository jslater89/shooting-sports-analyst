import 'package:uspsa_result_viewer/data/match/practical_match.dart';
import 'package:uspsa_result_viewer/data/match/relative_scores.dart';
import 'package:uspsa_result_viewer/data/ranking/model/rating_change.dart';
import 'package:uspsa_result_viewer/data/ranking/model/rating_system.dart';

class PointsRatingEvent extends RatingEvent {
  PointsRatingEvent({
    required this.oldRating,
    required this.ratingChange,
    required PracticalMatch match,
    required RelativeScore score,
    List<String> info = const [],
  }) : super(match: match, score: score, info: info);

  PointsRatingEvent.copy(PointsRatingEvent other) :
      this.oldRating = other.oldRating,
      this.ratingChange = other.ratingChange,
      super.copy(other);

  @override
  void apply(RatingChange change) {
    ratingChange += change.change[RatingSystem.ratingKey]!;
  }

  @override
  final double oldRating;

  @override
  double ratingChange;
}