import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/ranking/rater_types.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/openskill/openskill_rater.dart';

class OpenskillRatingEvent extends RatingEvent {
  double muChange;
  double sigmaChange;

  double initialMu;

  double get oldRating => initialMu;
  double get ratingChange => muChange;

  OpenskillRatingEvent({
    required this.initialMu,
    required this.muChange,
    required this.sigmaChange,
    required PracticalMatch match,
    Stage? stage,
    required RelativeScore score,
    List<String> info = const [],
  }) : super(
    match: match,
    stage: stage,
    score: score,
    info: info,
  );

  @override
  void apply(RatingChange change) {
    muChange += change.change[OpenskillRater.muKey]!;
    sigmaChange += change.change[OpenskillRater.sigmaKey]!;
  }

  OpenskillRatingEvent.copy(OpenskillRatingEvent other) :
      this.initialMu = other.initialMu,
      this.muChange = other.muChange,
      this.sigmaChange = other.sigmaChange,
      super.copy(other);
}