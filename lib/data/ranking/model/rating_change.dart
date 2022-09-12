import 'package:uspsa_result_viewer/data/model.dart';

class RatingChange {
  final Map<String, double> change;
  final List<String> info;

  RatingChange({required this.change, this.info = const []});

  @override
  String toString() {
    return "$change";
  }
}

abstract class RatingEvent {
  String get eventName => "${match.name}" + (stage == null ? "" : " - ${stage!.name}");

  PracticalMatch match;
  Stage? stage;
  RelativeScore score;
  List<String> info;

  double get ratingChange;
  double get oldRating;
  double get newRating => oldRating + ratingChange;

  RatingEvent({required this.match, this.stage, required this.score, this.info = const []});

  void apply(RatingChange change);

  RatingEvent.copy(RatingEvent other) :
        this.match = other.match,
        this.stage = other.stage,
        this.score = other.score,
        this.info = [...other.info];
}
