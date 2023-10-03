import 'package:collection/collection.dart';
import 'package:uspsa_result_viewer/data/sport/sport.dart';

sealed class MatchScoreCalculation{}

/// In relative stage finish scoring, finish percentage on a stage scores
/// you a proportion of the stage's value: 95% finish on a 100-point stage
/// gets you 95 match points.
final class RelativeStageFinishScoring extends MatchScoreCalculation {
  /// If not null, all stages are worth this many match points, like in USPSA
  /// multigun: time plus yields a percentage stage finish, multiplied by
  /// fixedStageValue = 100 for match points.
  ///
  /// Otherwise, as USPSA scoring.
  final int? fixedStageValue;

  RelativeStageFinishScoring({this.fixedStageValue});
}

/// In cumulative scoring, the scores from each stage are tallied up, and
/// the sums are compared directly.
///
/// In something like Bianchi Cup, points are tallied and the highest
/// wins. In something like IDPA, times are tallied and the lowest wins.
final class CumulativeScoring extends MatchScoreCalculation {}

class RawScore {
  SportScoring scoring;
  double rawTime;
  Map<ScoringEvent, int> scoringEvents;
  Map<ScoringEvent, int> penaltyEvents;
  
  List<Map<ScoringEvent, int>> get _scoreMaps => [scoringEvents, penaltyEvents];
  
  int get points => _scoreMaps.points;
  double get finalTime => rawTime + _scoreMaps.timeAdjustment;

  RawScore({
    required this.scoring,
    this.rawTime = 0.0,
    required this.scoringEvents,
    this.penaltyEvents = const {},
  });
  
  double get hitFactor {
    if(rawTime == 0 && scoringEvents.isEmpty) {
      // DNF
      return 0;
    }
    else if(rawTime == 0) {
      // Fixed time?
      return points.toDouble();
    }
    else {
      return points / rawTime;
    }
  }
}

extension ScoreUtilities on Map<ScoringEvent, int> {
  int get points {
    int total = 0;
    for(var s in keys) {
      int occurrences = this[s]!;
      total += s.pointChange * occurrences;
    }
    return total;
  }
  
  double get timeAdjustment {
    double total = 0;
    for(var s in keys) {
      int occurrences = this[s]!;
      total += s.timeChange * occurrences;
    }
    return total;
  }
}

extension ScoreListUtilities on List<Map<ScoringEvent, int>> {
  int get points {
    return this.map((m) => m.points).sum;
  }
  double get timeAdjustment {
    return this.map((m) => m.timeAdjustment).sum;
  }
}