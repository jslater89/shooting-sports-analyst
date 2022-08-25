import 'package:uspsa_result_viewer/data/match/relative_scores.dart';

class RatingChange {
  final double change;
  final List<String> info;

  RatingChange({required this.change, this.info = const []});
}

class RatingEvent {
  String eventName;
  RelativeScore score;
  double ratingChange;
  List<String> info;

  RatingEvent({required this.eventName, required this.score, this.ratingChange = 0, this.info = const []});

  RatingEvent.copy(RatingEvent other) :
        this.eventName = other.eventName,
        this.score = other.score,
        this.ratingChange = other.ratingChange,
        this.info = [...other.info];
}
