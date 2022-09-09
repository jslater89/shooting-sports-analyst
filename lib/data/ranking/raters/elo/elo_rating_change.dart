import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/ranking/model/rating_change.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/elo/multiplayer_percent_elo_rater.dart';

class EloRatingEvent extends RatingEvent {
  double ratingChange;
  final double oldRating;

  double error;

  EloRatingEvent({required this.oldRating, required String eventName, required RelativeScore score, List<String> info = const [], required this.ratingChange, this.error = 0})
      : super(eventName: eventName, score: score, info: info);

  EloRatingEvent.copy(EloRatingEvent other) :
      this.error = other.error,
      this.oldRating = other.oldRating,
      this.ratingChange = other.ratingChange,
      super.copy(other);

  @override
  void apply(RatingChange change) {
    ratingChange += change.change[MultiplayerPercentEloRater.ratingKey]!;
    error = change.change[MultiplayerPercentEloRater.errorKey]!;
  }
}