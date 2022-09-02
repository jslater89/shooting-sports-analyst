import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/ranking/rater_types.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/openskill/openskill_rater.dart';

class OpenskillRatingEvent extends RatingEvent {
  double muChange;
  double sigmaChange;

  double get ratingChange => sigmaChange;

  OpenskillRatingEvent({
    required this.muChange,
    required this.sigmaChange,
    required String eventName,
    required RelativeScore score,
    List<String> info = const [],
  }) : super(
    eventName: eventName,
    score: score,
    info: info,
  );

  @override
  void apply(RatingChange change) {
    muChange += change.change[OpenskillRater.muKey]!;
    sigmaChange += change.change[OpenskillRater.sigmaKey]!;
  }

  OpenskillRatingEvent.copy(OpenskillRatingEvent other) :
      this.muChange = other.muChange,
      this.sigmaChange = other.sigmaChange,
      super.copy(other);
}