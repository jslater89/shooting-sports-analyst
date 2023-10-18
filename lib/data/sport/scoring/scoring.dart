import 'package:collection/collection.dart';
import 'package:uspsa_result_viewer/data/sport/sport.dart';
import 'package:uspsa_result_viewer/util.dart';

/// Match scoring is how a list of absolute scores are converted to relative
/// scores, and then to overall match scores.
sealed class MatchScoring {
}

/// In relative stage finish scoring, finish percentage on a stage scores
/// you a proportion of the stage's value: 95% finish on a 100-point stage
/// gets you 95 match points.
final class RelativeStageFinishScoring extends MatchScoring {
  /// If not null, all stages are worth this many match points, like in USPSA
  /// multigun: time plus yields a percentage stage finish, multiplied by
  /// fixedStageValue = 100 for match points.
  ///
  /// Otherwise, as USPSA scoring, where stages are worth their total point
  /// value.
  final int? fixedStageValue;

  /// If true, treat stages with 'points' scoring like USPSA fixed time stages.
  final bool pointsAreUSPSAFixedTime;

  RelativeStageFinishScoring({this.fixedStageValue, this.pointsAreUSPSAFixedTime = false});
}

/// In cumulative scoring, the scores from each stage are tallied up, and
/// the sums are compared directly.
///
/// In something like Bianchi Cup, points are tallied and the highest
/// wins. In something like IDPA, times are tallied and the lowest wins.
final class CumulativeScoring extends MatchScoring {
  /// True if a higher cumulative score is better than a lower one.
  ///
  /// Time-plus sports will set this to false. Other sports will set it
  /// to true.
  bool highScoreWins;
  bool get lowScoreWins => !highScoreWins;

  CumulativeScoring({this.highScoreWins = true});
}

/// Stage scoring is how a list of scoring events are converted into an absolute score:
/// time divided by points makes hit factor, time plus points down makes time plus, sum of
/// points makes points.
enum StageScoring {
  /// A sport scored like USPSA or PCSL: points divided by time is a hit factor for stage score.
  hitFactor,
  /// A sport scored like IDPA or multigun: score is raw time, plus penalties.
  timePlus,
  /// A sport scored like sporting clays or bullseye: score is determined entirely by hits on target.
  points,
}

/// A relative score is a raw score placed against other scores.
abstract class RelativeScore {
  int place;
  double ratio;
  double get percentage => ratio * 100;

  RelativeScore({
    required this.place,
    required this.ratio,
  });
}

/// A relative match score is an overall score for an entire match.
class RelativeMatchScore extends RelativeScore {
  List<RelativeStageScore> stageScores;
  RawScore total;

  RelativeMatchScore({
    required this.stageScores,
    required super.place,
    required super.ratio,
  }) : total = stageScores.map((e) => e.score).sum;
}

class RelativeStageScore extends RelativeScore {
  RawScore score;
  RelativeStageScore({
    required this.score,
    required super.place,
    required super.ratio,
  });
}

/// A raw score is what we store in the DB, and is what we can determine entirely from the shooter's
/// time and hits.
class RawScore {
  StageScoring scoring;
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

/// A ScoringEvent is the minimal unit of score change in a shooting sports
/// discipline, based on a hit on target.
class ScoringEvent {
  final String name;

  final int pointChange;
  final double timeChange;

  /// bonus indicates that this hit is a bonus/tiebreaker score with no other scoring implications:
  ///
  /// An ICORE stage with a time bonus for a X-ring hits is _not_ a bonus like this, because it scores
  /// differently than an A. A Bianchi X hit _is_ a bonus: it scores 10 points, but also increments
  /// your X count.
  final bool bonus;
  final String bonusLabel;

  const ScoringEvent(this.name, {this.pointChange = 0, this.timeChange = 0, this.bonus = false, this.bonusLabel = "X"});
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

extension ScoreMapUtilities on List<Map<ScoringEvent, int>> {
  int get points {
    return this.map((m) => m.points).sum;
  }
  double get timeAdjustment {
    return this.map((m) => m.timeAdjustment).sum;
  }
}

extension ScoreListUtilities on Iterable<RawScore> {
  RawScore get sum {
    Map<ScoringEvent, int> scoringEvents = {};
    Map<ScoringEvent, int> penaltyEvents = {};
    double rawTime = 0;
    StageScoring scoring = StageScoring.hitFactor;

    for(var s in this) {
      scoring = s.scoring;
      for(var e in s.scoringEvents.keys) {
        scoringEvents[e] ??= 0;
        scoringEvents.addTo(e, s.scoringEvents[e]!);
      }

      for(var e in s.penaltyEvents.keys) {
        penaltyEvents[e] ??= 0;
        penaltyEvents.addTo(e, s.penaltyEvents[e]!);
      }

      rawTime += s.rawTime;
    }

    return RawScore(scoring: scoring, scoringEvents: scoringEvents, penaltyEvents: penaltyEvents, rawTime: rawTime);
  }
}