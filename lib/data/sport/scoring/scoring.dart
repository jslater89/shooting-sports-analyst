/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:collection';

import 'package:collection/collection.dart';
import 'package:uspsa_result_viewer/data/sport/match/match.dart';
import 'package:uspsa_result_viewer/data/sport/shooter/shooter.dart';
import 'package:uspsa_result_viewer/data/sport/sport.dart';
import 'package:uspsa_result_viewer/ui/result_page.dart';
import 'package:uspsa_result_viewer/util.dart';

/// Match scoring is how a list of absolute scores are converted to relative
/// scores, and then to overall match scores.
sealed class MatchScoring {
  /// Calculate match scores, given a list of shooters, and optionally a list of stages to limit to.
  Map<MatchEntry, RelativeMatchScore> calculateMatchScores({
    required List<MatchEntry> shooters,
    required List<MatchStage> stages,
    bool scoreDQ = true,
    MatchPredictionMode predictionMode = MatchPredictionMode.none,
  });
}

/// In relative stage finish scoring, finish percentage on a stage scores
/// you a proportion of the stage's value: 95% finish on a 100-point stage
/// gets you 95 match points.
///
/// Stages in matches scored with RelativeStageFinishScoring must have
/// maxPoints, or else [fixedStageValue] must be set.
final class RelativeStageFinishScoring extends MatchScoring {
  /// If not null, all stages are worth this many match points, like in USPSA
  /// multigun: time plus yields a percentage stage finish, multiplied by
  /// fixedStageValue = 100 for match points.
  ///
  /// Otherwise, as USPSA scoring, where stages are worth their total point
  /// value.
  final int? fixedStageValue;

  /// If true, treat stages with 'points' scoring like USPSA fixed time stages.
  ///
  /// Percentages are relative to the winner, but stage points are the number
  /// of points scored.
  final bool pointsAreUSPSAFixedTime;

  RelativeStageFinishScoring({this.fixedStageValue, this.pointsAreUSPSAFixedTime = false});

  @override
  Map<MatchEntry, RelativeMatchScore> calculateMatchScores({
    required List<MatchEntry> shooters, required List<MatchStage> stages,
    bool scoreDQ = true, MatchPredictionMode predictionMode = MatchPredictionMode.none,
  }) {
    if(shooters.length == 0 || stages.length == 0) return {};

    Map<MatchEntry, RelativeMatchScore> matchScores = {};
    Map<MatchEntry, Map<MatchStage, RelativeStageScore>> stageScores = {};

    // First, fill in the stageScores map with relative placements on each stage.
    for(var stage in stages) {
      Map<MatchEntry, RawScore> scores = {};

      StageScoring scoring = stage.scoring;
      RawScore? bestScore = null;

      // Find the high score on the stage.
      for(var shooter in shooters) {
        var stageScore = shooter.scores[stage];

        if(stageScore == null) {
          stageScore = RawScore(scoring: scoring, scoringEvents: {});
          shooter.scores[stage] = stageScore;
        }

        scores[shooter] = stageScore;
        
        // A DNF/zero score doesn't count for best.
        if(stageScore.dnf) continue;
        
        if(bestScore == null || scoring.firstScoreBetter(stageScore, bestScore)) {
          bestScore = stageScore;
        }
      }

      if(bestScore == null) {
        // Nobody completed this stage, so move on to the next one
        continue;
      }

      // How many match points the stage is worth.
      int stageValue = fixedStageValue ?? stage.maxPoints;

      // Sort the shooters by raw score on this stage, so we can assign places in one step.
      var sortedShooters = scores.keys.sorted((a, b) => scoring.compareScores(scores[b]!, scores[a]!));

      // Based on the high score, calculate ratios.
      for(int i = 0; i < sortedShooters.length; i++) {
        var shooter = sortedShooters[i];
        var score = scores[shooter]!;
        var ratio = scoring.ratio(score, bestScore);
        late double points;

        if(shooter.dq && !scoreDQ) {
          points = 0;
          ratio = 0;
        }
        else if(scoring is PointsScoring && pointsAreUSPSAFixedTime) {
          points = score.points.toDouble();
        }
        else {
          points = stageValue * ratio;
        }

        var relativeStageScore = RelativeStageScore(
          score: score,
          place: i + 1,
          ratio: ratio,
          points: points,
        );
        stageScores[shooter] ??= {};
        stageScores[shooter]![stage] = relativeStageScore;
      }
    }

    // Next, build match point totals for each shooter, summing the points available
    // per stage.
    Map<MatchEntry, double> stageScoreTotals = {};
    double bestTotalScore = 0;
    for(var s in shooters) {
      var shooterStageScores = stageScores[s];

      if(shooterStageScores == null) {
        throw StateError("shooter has no stage scores");
      }

      var totalScore = shooterStageScores.values.map((e) => e.points!).sum;
      stageScoreTotals[s] = totalScore;
      if(totalScore > bestTotalScore) {
        bestTotalScore = totalScore;
      }
    }

    // Sort the shooters by stage score totals and create relative match scores.
    var sortedShooters = shooters.sorted((a, b) => stageScoreTotals[b]!.compareTo(stageScoreTotals[a]!));
    for(int i = 0; i < sortedShooters.length; i++) {
      var shooter = sortedShooters[i];
      var shooterStageScores = stageScores[shooter]!;
      var totalScore = stageScoreTotals[shooter]!;

      matchScores[shooter] = RelativeMatchScore(
        stageScores: shooterStageScores,
        place: i + 1,
        ratio: totalScore / bestTotalScore,
        points: totalScore,
      );
    }

    return matchScores;
  }
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

  Map<MatchEntry, RelativeMatchScore> calculateMatchScores({
    required List<MatchEntry> shooters, required List<MatchStage> stages,
    bool scoreDQ = true, MatchPredictionMode predictionMode = MatchPredictionMode.none,
  }) {
    if(shooters.length == 0 || stages.length == 0) return {};

    Map<MatchEntry, RelativeMatchScore> matchScores = {};
    Map<MatchEntry, Map<MatchStage, RelativeStageScore>> stageScores = {};

    // hasDNF indicates when a shooter should be sorted to the bottom of the scores, either
    // because of a DQ or a lowScoreWins stage DNF.
    Set<MatchEntry> matchDNF = {};

    for(var stage in stages) {
      Set<MatchEntry> stageDNF = {};
      Map<MatchEntry, RawScore> scores = {};

      StageScoring scoring = stage.scoring;
      RawScore? bestScore = null;

      // Find the high score on the stage.
      for(var shooter in shooters) {
        var stageScore = shooter.scores[stage];

        if(stageScore == null) {
          stageScore = RawScore(scoring: scoring, scoringEvents: {});
          shooter.scores[stage] = stageScore;
        }

        scores[shooter] = stageScore;

        // Score DQ/DNF logic is complicated for cumulative matches.
        // If a lowScoreWins shooter DNFs a stage, they cannot have a
        // match score—they'd have a 0 where everyone else has an N, so
        // they would finish ahead of people they 'lost to' by DNFing.
        // If a highScoreWins shooter DNFs a stage, that's fine. They get
        // a 0, and finish behind anyone who got points.
        // If a shooter in either cumulative mode DQs, and scoreDQ is off,
        // they get added to the DNF lists and sort to the end of all stages
        // and the match score. If scoreDQ is on (and a lowScoreWins shooter
        // did not DNF this stage), they count for this stage.
        // A lowScoreWins shooter will be added to the match DNF list if they
        // DNF any stage for any reason, or if they DQ and scoreDQ is off. A
        // highScoreWins shooter will only be added to the match DNF list if
        // score DQ is off.
        if((stageScore.dnf && lowScoreWins) || (!scoreDQ && shooter.dq)) {
          stageDNF.add(shooter);
          matchDNF.add(shooter);
          continue;
        }

        if(bestScore == null || scoring.firstScoreBetter(stageScore, bestScore)) {
          bestScore = stageScore;
        }
      }

      if(bestScore == null) {
        // Nobody completed this stage, so move on to the next one
        continue;
      }

      // Sort the shooters by raw score on this stage, so we can assign places in one step.
      var sortedShooters = scores.keys.sorted((a, b) {
        // If both are DNF/DQ, sort equally.
        if(stageDNF.contains(a) && stageDNF.contains(b)) return a.lastName.compareTo(b.lastName);
        // If A is DNF and B is not DNF, A sorts after B, and vice versa.
        else if(stageDNF.contains(a) && !stageDNF.contains(b)) return 1;
        else if(!stageDNF.contains(a) && stageDNF.contains(b)) return -1;
        // If neither A nor B is DNF, sort by descending order of finish.
        return scoring.compareScores(scores[b]!, scores[a]!);
      });

      // Based on the high score, calculate ratios.
      // In the event that a shooter is DNF on this stage, their points will be 0, and they'll be
      // sorted to the end because of the sort in sortedShooters.
      for(int i = 0; i < sortedShooters.length; i++) {
        var shooter = sortedShooters[i];
        var score = scores[shooter]!;

        // Ratio is 0.0 for lowScoreWins stageDNF shooters. Points is 0 because of DNF.
        var ratio = scoring.ratio(score, bestScore);
        if(lowScoreWins && stageDNF.contains(shooter)) ratio = 0.0;

        var points = scoring.interpret(score);
        var relativeStageScore = RelativeStageScore(
          score: score,
          place: i + 1,
          ratio: ratio,
          points: points.toDouble(),
        );
        stageScores[shooter] ??= {};
        stageScores[shooter]![stage] = relativeStageScore;
      }
    }

    // Next, build match point totals for each shooter, summing the points available
    // per stage.
    Map<MatchEntry, double> stageScoreTotals = {};
    double bestTotalScore = highScoreWins ? 0 : double.maxFinite;
    for(var s in shooters) {
      var shooterStageScores = stageScores[s];

      if(shooterStageScores == null) {
        throw StateError("shooter has no stage scores");
      }

      var totalScore = shooterStageScores.values.map((e) => e.points!).sum;
      stageScoreTotals[s] = totalScore;
      if(lowScoreWins) {
        // Match DNFs can't be the best total score.
        if(totalScore < bestTotalScore && !matchDNF.contains(s)) {
          bestTotalScore = totalScore;
        }
      }
      else {
        if (totalScore > bestTotalScore) {
          bestTotalScore = totalScore;
        }
      }
    }

    // Sort the shooters by stage score totals.
    // People on the match DNF list get sorted to the end of the list.
    late List<MatchEntry> sortedShooters;
    if(lowScoreWins) {
      sortedShooters = shooters.sorted((a, b) {
        // If both are DNF/DQ, sort equally.
        if(matchDNF.contains(a) && matchDNF.contains(b)) return a.lastName.compareTo(b.lastName);
        // If A is DNF and B is not DNF, A sorts after B, and vice versa.
        else if(matchDNF.contains(a) && !matchDNF.contains(b)) return 1;
        else if(!matchDNF.contains(a) && matchDNF.contains(b)) return -1;

        return stageScoreTotals[a]!.compareTo(stageScoreTotals[b]!);
      });
    }
    else {
      sortedShooters = shooters.sorted((a, b) {
        // If both are DNF/DQ, sort equally.
        if(matchDNF.contains(a) && matchDNF.contains(b)) return a.lastName.compareTo(b.lastName);
        // If A is DNF and B is not DNF, A sorts after B, and vice versa.
        else if(matchDNF.contains(a) && !matchDNF.contains(b)) return 1;
        else if(!matchDNF.contains(a) && matchDNF.contains(b)) return -1;

        return stageScoreTotals[b]!.compareTo(stageScoreTotals[a]!);
      });
    }

    for(int i = 0; i < sortedShooters.length; i++) {
      var shooter = sortedShooters[i];
      var shooterStageScores = stageScores[shooter]!;
      var totalScore = stageScoreTotals[shooter]!;

      // In lowScoreWins mode, if someone is on the match DNF list, we can't
      // give them a valid score, so their total score becomes 0, as does their
      // ratio.
      if(lowScoreWins && matchDNF.contains(shooter)) {
        totalScore = 0.0;
      }

      var ratio = 0.0;
      if(lowScoreWins) {
        if(totalScore != 0.0) {
          ratio = bestTotalScore / totalScore;
        }
      }
      else {
        ratio = totalScore / bestTotalScore;
      }

      matchScores[shooter] = RelativeMatchScore(
        stageScores: shooterStageScores,
        place: i + 1,
        ratio: ratio,
        points: totalScore,
      );
    }

    return matchScores;
  }
}

sealed class StageScoring {
  /// Provide a comparative value for a raw score, using this scoring system.
  num interpret(RawScore score);

  /// If true, better scores in this scoring system are higher numeric values,
  /// and lower scores are worse.
  ///
  /// The opposite is true when false.
  bool get highScoreBest;

  /// The opposite of [highScoreBest].
  bool get lowScoreBest => !highScoreBest;

  String get dbString => this.runtimeType.toString();

  /// Returns >0 if a is better than b, 0 if they are equal, and <0 is b is better than a.
  int compareScores(RawScore a, RawScore b) {
    var aInt = interpret(a);
    var bInt = interpret(b);
    if(highScoreBest) {
      if (aInt > bInt) return 1;
      if (aInt < bInt) return -1;
      return 0;
    }
    else {
      if (aInt < bInt) return 1;
      if (aInt > bInt) return -1;
      return 0;
    }
  }

  /// Returns true if a is better than b.
  bool firstScoreBetter(RawScore a, RawScore b) {
    return compareScores(a, b) > 0;
  }

  /// Returns the ratio of [score] to [comparedTo].
  ///
  /// If score is 95 and comparedTo is 100, this will return
  /// 0.95 for a highScoreBest scoring.
  double ratio(RawScore score, RawScore comparedTo) {
    if(highScoreBest) {
      return interpret(score) / interpret(comparedTo);
    }
    else {
      return interpret(comparedTo) / interpret(score);
    }
  }

  const StageScoring();

  static StageScoring fromDbString(String string) {
    if(string.startsWith(const HitFactorScoring().dbString)) return const HitFactorScoring();
    else if(string.startsWith(const TimePlusScoring().dbString)) return const TimePlusScoring();
    else if(string.startsWith(const PointsScoring(highScoreBest: true).dbString)) {
      var highScoreBest = string.split("|")[1];
      if(highScoreBest == "true") return const PointsScoring(highScoreBest: true);
      else return const PointsScoring(highScoreBest: false);
    }
    else return const IgnoredScoring();
  }
}

class HitFactorScoring extends StageScoring {
  num interpret(RawScore score) => score.hitFactor;
  bool get highScoreBest => true;

  const HitFactorScoring();
}

class TimePlusScoring extends StageScoring {
  num interpret(RawScore score) => score.finalTime;
  bool get highScoreBest => false;

  const TimePlusScoring();
}

class PointsScoring extends StageScoring {
  num interpret(RawScore score) => score.points;
  final bool highScoreBest;

  String get dbString => "${this.runtimeType.toString()}|$highScoreBest";

  const PointsScoring({this.highScoreBest = true});
}

class IgnoredScoring extends StageScoring {
  num interpret(RawScore score) => 0;
  bool get highScoreBest => true;

  const IgnoredScoring();
}

/// A relative score is a raw score placed against other scores.
abstract class RelativeScore {
  int place;
  double ratio;
  double get percentage => ratio * 100;

  /// points holds any intermediate or calculated values we need:
  /// in relative finish scoring, for instance, the number of stage points
  /// earned in this score.
  double? points;

  RelativeScore({
    required this.place,
    required this.ratio,
    this.points,
  });
}

/// A relative match score is an overall score for an entire match.
class RelativeMatchScore extends RelativeScore {
  Map<MatchStage, RelativeStageScore> stageScores;
  RawScore total;

  RelativeMatchScore({
    required this.stageScores,
    required super.place,
    required super.ratio,
    super.points,
  }) : total = stageScores.values.map((e) => e.score).sum;
}

class RelativeStageScore extends RelativeScore {
  RawScore score;
  RelativeStageScore({
    required this.score,
    required super.place,
    required super.ratio,
    super.points,
  });
}

/// A raw score is what we store in the DB, and is what we can determine entirely from the shooter's
/// time and hits.
class RawScore {
  /// How this score should be interpreted.
  StageScoring scoring;

  /// The raw time on the shot timer. Use 0 for untimed sports.
  double rawTime;

  /// Scoring events for this score: that is, events caused by a hit or
  /// lack of hit on a target.
  Map<ScoringEvent, int> scoringEvents;

  /// Penalty events for this score: that is, events caused by a competitor's
  /// actions or failures to act outside of hits or misses on targets.
  Map<ScoringEvent, int> penaltyEvents;
  List<double> stringTimes;
  
  List<Map<ScoringEvent, int>> get _scoreMaps => [scoringEvents, penaltyEvents];
  
  int get points => _scoreMaps.points;
  double get finalTime => rawTime + _scoreMaps.timeAdjustment;

  RawScore({
    required this.scoring,
    this.rawTime = 0.0,
    required this.scoringEvents,
    this.penaltyEvents = const {},
    this.stringTimes = const [],
  });

  bool get dnf =>
      (this.scoring is HitFactorScoring && scoringEvents.length == 0 && rawTime == 0.0)
      || (this.scoring is TimePlusScoring && rawTime == 0.0)
      || (this.scoring is PointsScoring && points == 0);

  /// The hit factor represented by this score.
  ///
  /// Returns 0 (DNF) when raw time is zero, unless [scoring] is
  /// [PointsScoring], in which case this is treated like a USPSA
  /// fixed time stage, and the raw point total is returned as a
  /// 'hit factor'.
  double get hitFactor {
    if(rawTime == 0.0) {
      if(rawTime == 0.0 && scoring is PointsScoring && points > 0) {
        return points.toDouble();
      }
      // DNF
      return 0;
    }
    else {
      return points / rawTime;
    }
  }
}

/// A ScoringEvent is the minimal unit of score change in a shooting sports
/// discipline, based on a hit on target.
class ScoringEvent implements NameLookupEntity {
  final String name;

  /// Unused, for NameLookupEntity
  String get shortName => "";
  /// Unused, for NameLookupEntity
  List<String> get alternateNames => [];

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
    StageScoring scoring = HitFactorScoring();

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