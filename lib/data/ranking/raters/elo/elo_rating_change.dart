import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/ranking/model/rating_change.dart';
import 'package:uspsa_result_viewer/data/ranking/model/rating_system.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/elo/multiplayer_percent_elo_rater.dart';

class EloRatingEvent extends RatingEvent {
  double ratingChange;
  final double oldRating;

  double baseK;
  double effectiveK;

  double error;

  EloRatingEvent({
    required this.oldRating,
    required PracticalMatch match,
    Stage? stage,
    required RelativeScore score,
    List<String> info = const [],
    required this.ratingChange,
    this.error = 0,
    required this.baseK,
    required this.effectiveK,
  }) : super(match: match, stage: stage, score: score, info: info);

  EloRatingEvent.copy(EloRatingEvent other) :
      this.error = other.error,
      this.oldRating = other.oldRating,
      this.ratingChange = other.ratingChange,
      this.baseK = other.baseK,
      this.effectiveK = other.effectiveK,
      super.copy(other);

  @override
  void apply(RatingChange change) {
    ratingChange += change.change[RatingSystem.ratingKey]!;
    error = change.change[MultiplayerPercentEloRater.errorKey]!;
    baseK = change.change[MultiplayerPercentEloRater.baseKKey]!;
    effectiveK = change.change[MultiplayerPercentEloRater.effectiveKKey]!;
  }
}