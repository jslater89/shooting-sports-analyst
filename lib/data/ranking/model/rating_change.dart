import 'package:uspsa_result_viewer/data/match/relative_scores.dart';

class RatingChange {
  final Map<String, double> change;
  final List<String> info;

  RatingChange({required this.change, this.info = const []});
}

abstract class RatingEvent {
  String eventName;
  RelativeScore score;
  List<String> info;

  double get ratingChange;

  RatingEvent({required this.eventName, required this.score, this.info = const []});

  void apply(RatingChange change);

  RatingEvent.copy(RatingEvent other) :
        this.eventName = other.eventName,
        this.score = other.score,
        this.info = [...other.info];
}