import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/ranking/model/rating_change.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/elo/multiplayer_percent_elo_rater.dart';

class EloRatingEvent extends RatingEvent {
  double ratingChange;

  EloRatingEvent({required String eventName, required RelativeScore score, List<String> info = const [], required this.ratingChange})
      : super(eventName: eventName, score: score, info: info);

  EloRatingEvent.copy(EloRatingEvent other) :
      this.ratingChange = other.ratingChange,
      super.copy(other);

  @override
  void apply(RatingChange change) {
    ratingChange += change.change[MultiplayerPercentEloRater.ratingKey]!;
  }
}