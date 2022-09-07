import 'package:collection/collection.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/ranking/rater.dart';

class RelativeMatchScore {
  RelativeMatchScore({required this.shooter});

  Shooter shooter;
  late RelativeScore total;

  /// Percent of match max points shot
  late double percentTotalPoints;

  Map<Stage, RelativeScore> stageScores = {};
}

extension MatchScoresToCSV on List<RelativeMatchScore> {
  String toCSV() {
    String csv = "Member#,Name,MatchPoints,Percentage\n";
    var sorted = this.sorted((a, b) => a.total.place.compareTo(b.total.place));

    for(var score in sorted) {
      csv += "${score.shooter.memberNumber},";
      csv += "${score.shooter.getName(suffixes: false)},";
      csv += "${score.total.relativePoints.toStringAsFixed(2)},";
      csv += "${(score.total.percent * 100).toStringAsFixed(2)}\n";
    }

    return csv;
  }
}

class RelativeScore {
  RelativeScore();
  late Score score;

  int place = -1;

  /// If null, treat this as a match score
  Stage? stage;

  /// For stage scores, calculate this off of
  /// hit factors and use to set relative points.
  double percent = 0;

  /// For match scores, total from stage scores
  /// and use to set percent.
  double relativePoints = 0;
}