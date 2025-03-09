/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:collection';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:isar/isar.dart';
import 'package:shooting_sports_analyst/data/match/practical_match.dart';
import 'package:shooting_sports_analyst/data/ranking/interface/rating_data_source.dart';
import 'package:shooting_sports_analyst/data/match/relative_scores.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/match_prediction.dart';
import 'package:shooting_sports_analyst/data/ranking/rater_types.dart';
import 'package:shooting_sports_analyst/data/ranking/legacy_loader/rating_history.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/fantasy_scoring_calculator.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/match_scoring.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/stage_scoring.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/shooter.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/ui/result_page.dart';
import 'package:shooting_sports_analyst/ui/widget/score_list.dart';
import 'package:shooting_sports_analyst/util.dart';

export 'package:shooting_sports_analyst/data/sport/scoring/stage_scoring.dart';
export 'package:shooting_sports_analyst/data/sport/scoring/match_scoring.dart';

SSALogger _log = SSALogger("Scoring");

/// A bare relative score is a relative score without any attached shooter.
abstract class BareRelativeScore {
  /// The ordinal place represented by this score: 1 for 1st, 2 for 2nd, etc.
  final int place;
  /// The ratio of this score to the winning score: 1.0 for the winner, 0.9 for a 90% finish,
  /// 0.8 for an 80% finish, etc.
  final double ratio;
  /// points holds the final score for this relative score, whether
  /// calculated or simply repeated from an attached [RawScore].
  ///
  /// In a [RelativeStageFinishScoring] match, it's the number of stage
  /// points or the total number of match points. In a [CumulativeScoring]
  /// match, it's the final points or time per stage/match.
  final double points;

  /// A convenience getter for [ratio] * 100.
  double get percentage => ratio * 100;

  const BareRelativeScore({
    required this.place,
    required this.ratio,
    required this.points,
  });
}

/// A relative score is a raw score placed against other scores.
abstract class RelativeScore extends BareRelativeScore {
  /// The shooter to whom this score belongs.
  final MatchEntry shooter;

  const RelativeScore({
    required this.shooter,
    required super.place,
    required super.ratio,
    required super.points,
  });

  RelativeScore.copy(RelativeScore other) :
    this.shooter = other.shooter,
    super(
      place: other.place,
      ratio: other.ratio,
      points: other.points,
    );
}

/// A relative match score is an overall score for an entire match.
class RelativeMatchScore extends RelativeScore {
  Map<MatchStage, RelativeStageScore> stageScores;
  RawScore total;

  RelativeMatchScore({
    required super.shooter,
    required this.stageScores,
    required super.place,
    required super.ratio,
    required super.points,
  }) : total = stageScores.values.map((e) => e.score).sum {
    var max = maxPoints();
    var actualPoints = stageScores.values.map((e) => e.score.getTotalPoints(countPenalties: true)).sum.toDouble();
    percentTotalPoints = actualPoints / max;
  }

  late double percentTotalPoints;
  double percentTotalPointsWithSettings({bool scoreDQ = true, bool countPenalties = true, Map<MatchStage, int> stageMaxPoints = const {}}) {
    if(scoreDQ && countPenalties && stageMaxPoints.isEmpty) {
      return percentTotalPoints;
    }

    var max = maxPoints(stageMaxPoints: stageMaxPoints);
    var actualPoints = stageScores.values.map((e) => !scoreDQ && shooter.dq ? 0 : e.score.getTotalPoints(countPenalties: countPenalties)).sum.toDouble();

    return actualPoints / max;
  }

  int maxPoints({Map<MatchStage, int> stageMaxPoints = const{}}) {
    int max = 0;
    for(var stage in stageScores.keys) {
      max += stageMaxPoints[stage] ?? stageScores[stage]!.stage!.maxPoints;
    }
    return max;
  }

  bool? _isDnf;
  bool get isDnf {
    if(_isDnf == null) {
      _isDnf = stageScores.values.any((s) => s.isDnf);
    }
    return _isDnf!;
  }

  bool get hasResults {
    for(var s in stageScores.values) {
      if(!s.score.dnf) {
        return true;
      }
    }

    return false;
  }

  bool get isComplete {
    for(var s in stageScores.values) {
      if(s.score.dnf) {
        return false;
      }
    }

    return true;
  }
}

class RelativeStageScore extends RelativeScore {
  MatchStage stage;
  RawScore score;
  RelativeStageScore({
    required super.shooter,
    required this.stage,
    required this.score,
    required super.place,
    required super.ratio,
    required super.points,
  });

  double getPercentTotalPoints({bool scoreDQ = true, bool countPenalties = true, int? maxPoints}) {
    maxPoints ??= stage.maxPoints;
    if(maxPoints == 0) return 0.0;
    return !scoreDQ && shooter.dq ? 0.0 : score.getTotalPoints(countPenalties: countPenalties).toDouble() / maxPoints.toDouble();
  }

  bool? _isDnf;
  bool get isDnf {
    if(_isDnf == null) {
      _isDnf = score.dnf;
    }
    return _isDnf!;
  }
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
  Map<ScoringEvent, int> targetEvents;

  /// Penalty events for this score: that is, events caused by a competitor's
  /// actions or failures to act outside of hits or misses on targets.
  Map<ScoringEvent, int> penaltyEvents;

  /// Scoring event overrides for this score.
  Map<String, ScoringEventOverride> scoringOverrides;

  /// Whether this score resulted in a DQ.
  bool dq;

  /// A list of string times for this score.
  ///
  /// Used for display purposes only, at present time.
  List<double> stringTimes;

  /// The time this score was last modified.
  DateTime? modified;
  
  List<Map<ScoringEvent, int>> get _scoreMaps => [targetEvents, penaltyEvents];

  int get scoringEventCount => targetEventCount + penaltyEventCount;

  int get targetEventCount => targetEvents.values.sum;
  int get penaltyEventCount => penaltyEvents.values.sum;

  Map<ScoringEvent, int> mapForEvent(ScoringEvent event) {
    if(targetEvents.containsKey(event)) {
      return targetEvents;
    }
    else {
      return penaltyEvents;
    }
  }

  bool updateEventCount(ScoringEvent event, int count) {
    var changed = false;
    if(targetEvents.containsKey(event)) {
      targetEvents[event] = count;
      changed = true;
    }
    else if(penaltyEvents.containsKey(event)) {
      penaltyEvents[event] = count;
      changed = true;
    }
    if(changed) {
      clearCache();
    }
    return changed;
  }

  int countForEvent(ScoringEvent event) {
    var fromTarget = targetEvents[event];
    if(fromTarget != null) return fromTarget;

    var fromPenalty = penaltyEvents[event];
    if(fromPenalty != null) return fromPenalty;

    return 0;
  }
  
  int? _cachedPoints;
  int? _cachedPenaltyCount;
  int get points {
    if(_cachedPoints == null && scoringOverrides.isEmpty) {
      _cachedPoints = _scoreMaps.points;
    }
    else if(_cachedPoints == null) {
      _cachedPoints = _scoreMaps.pointsWithOverrides(scoringOverrides);
    }
    return _cachedPoints!;
  }

  int get penaltyCount { 
    if(_cachedPenaltyCount == null) {
      _cachedPenaltyCount = penaltyEvents.values.sum;
    }
    return _cachedPenaltyCount!;  
  }
  
  double? _cachedTimeAdjustment;
  double get finalTime {
    if(_cachedTimeAdjustment == null && scoringOverrides.isEmpty) {
      _cachedTimeAdjustment = _scoreMaps.timeAdjustment;
    }
    else if(_cachedTimeAdjustment == null) {
      _cachedTimeAdjustment = _scoreMaps.timeAdjustmentWithOverrides(scoringOverrides);
    }
    return rawTime + _cachedTimeAdjustment!;
  }

  void clearCache() {
    _cachedPoints = null;
    _cachedPenaltyCount = null;
    _cachedTimeAdjustment = null;
  }

  /// Get the sum of points for this score.
  /// 
  /// If [countPenalties] is true, all penalties are counted, including e.g. procedurals and other non-target penalties.
  /// 
  /// If [allowNegative] is true, the total may go below zero.
  /// 
  /// If [includeTargetPenalties] is true, penalties resulting from hits or lack of hits on targets (M, NS, etc.) are
  /// included in the total. For example, in a USPSA match, includeTargetPenalties = false would include only A, C, and
  /// D hits.
  int getTotalPoints({bool countPenalties = true, bool allowNegative = false, bool includeTargetPenalties = true}) {
    if(countPenalties) {
      if(allowNegative) {
        return points;
      }
      else {
        return max(0, points);
      }
    }
    else {
      if(includeTargetPenalties) {
        if(allowNegative) {
          return targetEvents.points;
        }
        else {
          return max(0, targetEvents.points);
        }
      }
      else {
        var positiveEvents = targetEvents.keys.where((e) => e.pointChange >= 0).toList();
        return positiveEvents.map((e) => targetEvents[e]! * e.pointChange).sum;
      }
    }
  }

  RawScore({
    required this.scoring,
    this.rawTime = 0.0,
    required this.targetEvents,
    this.penaltyEvents = const {},
    this.stringTimes = const [],
    this.scoringOverrides = const {},
    this.modified,
    this.dq = false,
  });

  bool get dnf =>
      (this.scoring is HitFactorScoring && targetEvents.length == 0 && rawTime == 0.0)
      || (this.scoring is TimePlusScoring && (this.scoring as TimePlusScoring).rawZeroWithEventsIsNonDnf && targetEvents.isEmpty && rawTime == 0.0)
      || (this.scoring is TimePlusScoring && !((this.scoring as TimePlusScoring).rawZeroWithEventsIsNonDnf) && rawTime == 0.0)
      || (this.scoring is PointsScoring && points == 0);
      // IgnoredScoring and TimePlusChronoScoring are never DNFs.

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
      return getTotalPoints() / rawTime;
    }
  }

  String get displayString => scoring.displayString(this);
  String get displayLabel => scoring.displayLabel(this);

  RawScore copy() {
    return RawScore(
      scoring: scoring,
      stringTimes: []..addAll(stringTimes),
      rawTime: rawTime,
      targetEvents: {...targetEvents},
      penaltyEvents: {...penaltyEvents},
      modified: modified,
      scoringOverrides: {...scoringOverrides},
    );
  }

  RawScore operator +(RawScore other) {
    Map<ScoringEvent, int> targetEvents = {};
    Map<ScoringEvent, int> penaltyEvents = {};
    for(var entry in this.targetEvents.entries) {
      targetEvents.incrementBy(entry.key, entry.value);
    }
    for(var entry in this.penaltyEvents.entries) {
      penaltyEvents.incrementBy(entry.key, entry.value);
    }
    for(var entry in other.targetEvents.entries) {
      targetEvents.incrementBy(entry.key, entry.value);
    }
    for(var entry in other.penaltyEvents.entries) {
      penaltyEvents.incrementBy(entry.key, entry.value);
    }

    var s = RawScore(
      scoring: this.scoring,
      rawTime: this.rawTime + other.rawTime,
      stringTimes: []..addAll(this.stringTimes)..addAll(other.stringTimes),
      targetEvents: targetEvents,
      penaltyEvents: penaltyEvents,
    );

    return s;
  }
  
  /// Returns true if this score differs from the other score.
  /// 
  /// Differs means 'has different times or hits'.
  bool equivalentTo(RawScore? other) {
    if(other == null) return false;

    // Scores are equal if raw time and scoring event counts are the same.
    if(rawTime != other.rawTime) return false;
    if(targetEvents.length != other.targetEvents.length) return false;
    if(penaltyEvents.length != other.penaltyEvents.length) return false;

    for(var e in targetEvents.keys) {
      if(targetEvents[e] != other.targetEvents[e]) return false;
    }

    for(var e in penaltyEvents.keys) {
      if(penaltyEvents[e] != other.penaltyEvents[e]) return false;
    }

    return true;
  }

  @override
  String toString() {
    return displayString;
  }
}

/// A ScoringEvent is the minimal unit of score change in a shooting sports
/// discipline, based on a hit on target.
class ScoringEvent extends NameLookupEntity {
  String get longName => name;
  final String name;
  final String shortName;
  final List<String> alternateNames;

  String get displayName => name;
  String get shortDisplayName => shortName.isNotEmpty ? shortName : name;

  final int pointChange;
  final double timeChange;
  final bool displayInOverview;

  /// If true, this scoring event's point or time change may vary. This event
  /// should be coalesced with other events of the same name to determine the
  /// number of hits of the event of that name.
  /// 
  /// This is necessary for ICORE: X-ring hits can vary not only across stages,
  /// but even on an individual stage, which is stupid and I hate it, because
  /// it's massively untidy to handle given the architecture I wrote for storing
  /// scores, which I *thought* was generic enough to handle anything.
  final bool variableValue;

  /// If this and variableValue are true, this scoring event is not the default
  /// points value for its name.
  final bool nondefaultPoints;

  /// If this and variableValue are true, this scoring event is not the default
  /// time value for its name.
  final bool nondefaultTime;

  final int sortOrder;

  /// bonus indicates that this hit is a bonus/tiebreaker score with no other scoring implications:
  ///
  /// An ICORE stage with a time bonus for a X-ring hits is _not_ a bonus like this, because it scores
  /// differently than an A. A Bianchi X hit _is_ a bonus: it scores 10 points, but also increments
  /// your X count.
  final bool bonus;
  final String bonusLabel;

  bool get fallback => false;

  /// If true, this is a dynamic event, i.e., one created by a match parser or other source, rather than
  /// a predefined event from a Sport definition.
  final bool dynamic;

  /// Returns true if this scoring event is positive, i.e., desirable,
  /// under the scoring rules of [sport].
  bool isPositive(Sport sport) {
    if(sport.matchScoring is RelativeStageFinishScoring) {
      if(sport.defaultStageScoring is HitFactorScoring) {
        return pointChange > 0 || timeChange < 0;
      }
      else if(sport.defaultStageScoring is TimePlusScoring) {
        return timeChange < 0;
      }
      else {
        return pointChange > 0;
      }
    }
    if(sport.matchScoring is CumulativeScoring) {
      if((sport.matchScoring as CumulativeScoring).lowScoreWins) {
        return pointChange < 0 || timeChange < 0;
      }
      else {
        return pointChange > 0 || timeChange > 0;
      }
    }
    else {
      return pointChange > 0 || timeChange < 0;
    }
  }

  const ScoringEvent(
    this.name, {
    this.displayInOverview = true,
    this.shortName = "",
    this.pointChange = 0,
    this.timeChange = 0,
    this.variableValue = false,
    this.nondefaultPoints = false,
    this.nondefaultTime = false,
    this.bonus = false,
    this.bonusLabel = "X",
    this.alternateNames = const [],
    this.sortOrder = 0,
    this.dynamic = false,
  });

  @override
  String toString() {
    return name;
  }

  ScoringEvent copyWith({
    int? pointChange,
    double? timeChange,
  }) {
    var pointsChanged = this.nondefaultPoints;
    var timeChanged = this.nondefaultTime;
    if(pointChange != null) {
      pointsChanged = true;
    }
    if(timeChange != null) {
      timeChanged = true;
    }
    return ScoringEvent(name,
      displayInOverview: displayInOverview,
      shortName: shortName,
      pointChange: pointChange ?? this.pointChange,
      timeChange: timeChange ?? this.timeChange,
      variableValue: variableValue,
      nondefaultPoints: pointsChanged,
      nondefaultTime: timeChanged,
      bonus: bonus,
      bonusLabel: bonusLabel,
      alternateNames: alternateNames,
      sortOrder: sortOrder,
    );
  }

  /// Two scoring events are equal if their base name is the same (not considering alternates!),
  /// their point and time changes are the same, and they both have the same default/non-default
  /// status.
  @override
  bool operator ==(Object other) {
    if(other is ScoringEvent) {
      return name == other.name 
        && this.timeChange == other.timeChange
        && this.pointChange == other.pointChange
        && this.nondefaultPoints == other.nondefaultPoints
        && this.nondefaultTime == other.nondefaultTime;
    }
    return false;
  }

  @override
  int get hashCode => Object.hash(name, timeChange, pointChange, nondefaultPoints, nondefaultTime);
}

/// Different values for scoring events for a particular score. This can come up
/// in ICORE, where X-ring time bonuses (when given in a stage brief) are not required
/// to be some particular value: 
class ScoringEventOverride {
  final String name;
  final int? pointChangeOverride;
  final double? timeChangeOverride;

  int get points => pointChangeOverride ?? 0;
  double get time => timeChangeOverride ?? 0;

  const ScoringEventOverride({
    required this.name,
    this.pointChangeOverride,
    this.timeChangeOverride,
  });

  ScoringEventOverride.time(this.name, this.timeChangeOverride) : pointChangeOverride = 0;
  ScoringEventOverride.points(this.name, this.pointChangeOverride) : timeChangeOverride = 0;
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

  int pointsWithOverrides(Map<String, ScoringEventOverride> overrides) {
    int total = 0;
    for(var s in keys) {
      int occurrences = this[s]!;
      var override = overrides[s.name];
      if(override != null) {
        total += override.points * occurrences;
      }
      else {
        total += s.pointChange * occurrences;
      }
    }
    return total;
  }

  double timeAdjustmentWithOverrides(Map<String, ScoringEventOverride> overrides) {
    double total = 0;
    for(var s in keys) {
      int occurrences = this[s]!;
      var override = overrides[s.name];
      if(override != null) {
        total += override.time * occurrences;
      }
      else {
        total += s.timeChange * occurrences;
      }
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

  int pointsWithOverrides(Map<String, ScoringEventOverride> overrides) {
    return this.map((m) => m.pointsWithOverrides(overrides)).sum;
  }
  double timeAdjustmentWithOverrides(Map<String, ScoringEventOverride> overrides) {
    return this.map((m) => m.timeAdjustmentWithOverrides(overrides)).sum;
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
      for(var e in s.targetEvents.keys) {
        var event = e;

        // We don't do this anywhere else, but we need to do it here so that
        // the sum of the changes is correct.
        if(s.scoringOverrides.containsKey(e.name)) {
          var override = s.scoringOverrides[e.name]!;
          event = e.copyWith(pointChange: override.pointChangeOverride, timeChange: override.timeChangeOverride);
        }
        scoringEvents.incrementBy(event, s.targetEvents[e]!);
      }

      for(var e in s.penaltyEvents.keys) {
        var event = e;

        if(s.scoringOverrides.containsKey(e.name)) {
          var override = s.scoringOverrides[e.name]!;
          event = e.copyWith(pointChange: override.pointChangeOverride, timeChange: override.timeChangeOverride);
        }
        penaltyEvents.incrementBy(event, s.penaltyEvents[e]!);
      }

      rawTime += s.rawTime;
    }

    return RawScore(scoring: scoring, targetEvents: scoringEvents, penaltyEvents: penaltyEvents, rawTime: rawTime);
  }
}

extension MatchScoresToCSV on List<RelativeMatchScore> {
  String toCSV({MatchStage? stage}) {
    String csv = "Member#,Name,MatchPoints,Percentage\n";
    var sorted = this.sorted((a, b) {
      if(stage != null) {
        if(a.stageScores.containsKey(stage) && b.stageScores.containsKey(stage)) {
          return a.stageScores[stage]!.place.compareTo(b.stageScores[stage]!.place);
        }
        else if(a.stageScores.containsKey(stage)) {
          return -1;
        }
        else if(b.stageScores.containsKey(stage)) {
          return 1;
        }
        else {
          return 0;
        }
      }
      else {
        return a.place.compareTo(b.place);
      }
    });

    for(var score in sorted) {
      var scoreOfInterest = stage == null ? score : score.stageScores[stage];
      csv += "${score.shooter.memberNumber},";
      csv += "${score.shooter.getName(suffixes: false)},";
      csv += "${stage == null ? score.total.points.toStringAsFixed(2) : scoreOfInterest?.points.toStringAsFixed(2) ?? 0},";
      csv += "${scoreOfInterest?.ratio.asPercentage() ?? 0}\n";
    }

    return csv;
  }
}

extension Sorting on List<RelativeMatchScore> {
  void sortByScore({MatchStage? stage}) {
    if(stage != null) {
      this.sort((a, b) {
        if(a.stageScores.containsKey(stage) && b.stageScores.containsKey(stage)) {
          return b.stageScores[stage]!.points.compareTo(a.stageScores[stage]!.points);
        }
        else {
          return 0;
        }
      });
    }
    else {
      this.sort((a, b) {
        return b.points.compareTo(a.points);
      });
    }
  }

  void sortByTime({MatchStage? stage, required bool scoreDQs, required MatchScoring scoring}) {
    if (stage != null) {
      this.sort((a, b) {
        if(!scoreDQs) {
          if (a.shooter.dq && !b.shooter.dq) {
            return 1;
          }
          if (b.shooter.dq && !a.shooter.dq) {
            return -1;
          }
        }

        if (a.stageScores.containsKey(stage) && b.stageScores.containsKey(stage)) {
          if(a.stageScores[stage]!.score.finalTime == 0 && b.stageScores[stage]!.score.finalTime == 0) return 0;
          else if(a.stageScores[stage]!.score.finalTime > 0 && b.stageScores[stage]!.score.finalTime == 0) return -1;
          else if(a.stageScores[stage]!.score.finalTime == 0 && b.stageScores[stage]!.score.finalTime > 0) return 1;

          return a.stageScores[stage]!.score.finalTime.compareTo(b.stageScores[stage]!.score.finalTime);
        }
        else {
          return 0;
        }
      });
    }
    else {
      this.sort((a, b) {
        if (!scoreDQs) {
          if (a.shooter.dq && !b.shooter.dq) {
            return 1;
          }
          else if (b.shooter.dq && !a.shooter.dq) {
            return -1;
          }
          else if(a.shooter.dq && b.shooter.dq) {
            return a.shooter.lastName.compareTo(b.shooter.lastName);
          }
        }

        if(scoring is CumulativeScoring) {
          if(scoring.lowScoreWins) {
            var aDnf = a.stageScores.values.any((s) => s.score.dnf);
            var bDnf = b.stageScores.values.any((s) => s.score.dnf);

            if(aDnf && !bDnf) {
              return 1;
            }
            else if(bDnf && !aDnf) {
              return -1;
            }
            else if(aDnf && bDnf) {
              return a.shooter.lastName.compareTo(b.shooter.lastName);
            }
          }
        }

        if(a.total.finalTime == 0 && b.total.finalTime == 0) return 0;
        else if(a.total.finalTime > 0 && b.total.finalTime == 0) return -1;
        else if(a.total.finalTime == 0 && b.total.finalTime > 0) return 1;

        return a.total.finalTime.compareTo(b.total.finalTime);
      });
    }
  }

  void sortByRawTime({MatchStage? stage, required bool scoreDQs, required MatchScoring scoring}) {
    if (stage != null) {
      this.sort((a, b) {
        if(!scoreDQs) {
          if (a.shooter.dq && !b.shooter.dq) {
            return 1;
          }
          if (b.shooter.dq && !a.shooter.dq) {
            return -1;
          }
        }

        if (a.stageScores.containsKey(stage) && b.stageScores.containsKey(stage)) {
          if(a.stageScores[stage]!.score.rawTime == 0 && b.stageScores[stage]!.score.rawTime == 0) return 0;
          else if(a.stageScores[stage]!.score.rawTime > 0 && b.stageScores[stage]!.score.rawTime == 0) return -1;
          else if(a.stageScores[stage]!.score.rawTime == 0 && b.stageScores[stage]!.score.rawTime > 0) return 1;

          return a.stageScores[stage]!.score.rawTime.compareTo(b.stageScores[stage]!.score.rawTime);
        }
        else {
          return 0;
        }
      });
    }
    else {
      this.sort((a, b) {
        if (!scoreDQs) {
          if (a.shooter.dq && !b.shooter.dq) {
            return 1;
          }
          if (b.shooter.dq && !a.shooter.dq) {
            return -1;
          }
        }

        if(scoring is CumulativeScoring) {
          if(scoring.lowScoreWins) {
            var aDnf = a.stageScores.values.any((s) => s.score.dnf);
            var bDnf = b.stageScores.values.any((s) => s.score.dnf);

            if(aDnf && !bDnf) {
              return 1;
            }
            else if(bDnf && !aDnf) {
              return -1;
            }
            else if(aDnf && bDnf) {
              return a.shooter.lastName.compareTo(b.shooter.lastName);
            }
          }
        }

        if(a.total.rawTime == 0 && b.total.rawTime == 0) return 0;
        else if(a.total.rawTime > 0 && b.total.rawTime == 0) return -1;
        else if(a.total.rawTime == 0 && b.total.rawTime > 0) return 1;

        return a.total.rawTime.compareTo(b.total.rawTime);
      });
    }
  }

  void sortByFantasyPoints({required Map<Shooter, FantasyScore>? fantasyScores}) {
    this.sort((a, b) {
      var aScore = fantasyScores?[a.shooter];
      var bScore = fantasyScores?[b.shooter];
      if(aScore == null && bScore == null) return a.shooter.lastName.compareTo(b.shooter.lastName);
      else if(aScore == null) return 1;
      else if(bScore == null) return -1;
      return bScore.points.compareTo(aScore.points);
    });
  }

  void sortByIdpaAccuracy({MatchStage? stage, required MatchScoring scoring}) {
    this.sort((a, b) {
      if (a.total.dnf && !b.total.dnf) {
        return 1;
      }
      if (b.total.dnf && !a.total.dnf) {
        return -1;
      }

      if(scoring is CumulativeScoring) {
        if(scoring.lowScoreWins) {
          var aDnf = a.stageScores.values.any((s) => s.score.dnf);
          var bDnf = b.stageScores.values.any((s) => s.score.dnf);

          if(aDnf && !bDnf) {
            return 1;
          }
          else if(bDnf && !aDnf) {
            return -1;
          }
          else if(aDnf && bDnf) {
            return a.shooter.lastName.compareTo(b.shooter.lastName);
          }
        }
      }

      var aPointDown = a.shooter.powerFactor.targetEvents.lookupByName("-1");
      var bPointDown = b.shooter.powerFactor.targetEvents.lookupByName("-1");
      var aNonThreat = a.shooter.powerFactor.penaltyEvents.lookupByName("Non-Threat");
      var bNonThreat = b.shooter.powerFactor.penaltyEvents.lookupByName("Non-Threat");

      if(aPointDown == null || bPointDown == null || aNonThreat == null || bNonThreat == null) {
        return 0;
      }

      RawScore? aScore, bScore;
      if(stage != null) {
        aScore = a.stageScores[stage]?.score;
        bScore = b.stageScores[stage]?.score;
      }
      else {
        aScore = a.total;
        bScore = b.total;
      }

      if(aScore == null && bScore == null) return 0;
      else if(aScore != null && bScore == null) return -1;
      else if(aScore == null && bScore != null) return 1;

      var aDown = aScore!.targetEvents[aPointDown] ?? 0;
      var bDown = bScore!.targetEvents[bPointDown] ?? 0;
      var aNT = aScore.penaltyEvents[aNonThreat] ?? 0;
      var bNT = bScore.penaltyEvents[bNonThreat] ?? 0;

      if(aNT == bNT) return aDown.compareTo(bDown);
      else return aNT.compareTo(bNT);
    });
  }

  void sortByAlphas({MatchStage? stage}) {
    if (stage != null) {
      this.sort((a, b) {
        if (a.stageScores.containsKey(stage) && b.stageScores.containsKey(stage)) {
          var aAlpha = a.shooter.powerFactor.targetEvents.lookupByName("A");
          var bAlpha = b.shooter.powerFactor.targetEvents.lookupByName("A");

          if(aAlpha == null || bAlpha == null) return 0;

          var aAlphaCount = a.stageScores[stage]!.score.targetEvents[aAlpha]!;
          var bAlphaCount = b.stageScores[stage]!.score.targetEvents[bAlpha]!;
          return bAlphaCount.compareTo(aAlphaCount);
        }
        else {
          return 0;
        }
      });
    }
    else {
      this.sort((a, b) {
        var aAlpha = a.shooter.powerFactor.targetEvents.lookupByName("A");
        var bAlpha = b.shooter.powerFactor.targetEvents.lookupByName("A");

        if(aAlpha == null || bAlpha == null) return 0;

        var aAlphaCount = a.total.targetEvents[aAlpha] ?? 0;
        var bAlphaCount = b.total.targetEvents[bAlpha] ?? 0;
        return bAlphaCount.compareTo(aAlphaCount);
      });
    }
  }

  void sortByAvailablePoints({MatchStage? stage, bool scoreDQ = true}) {
    // Available points is meaningless if max points is 0.
    if(this.length > 0) {
      if(this.first.stageScores.values.map((e) => e.stage.maxPoints).sum == 0) {
        sortByScore(stage: stage);
        return;
      }
    }

    if (stage != null) {
      this.sort((a, b) {
        if (a.stageScores.containsKey(stage) && b.stageScores.containsKey(stage)) {
          return b.stageScores[stage]!.getPercentTotalPoints(scoreDQ: scoreDQ).compareTo(a.stageScores[stage]!.getPercentTotalPoints(scoreDQ: scoreDQ));
        }
        else {
          return 0;
        }
      });
    }
    else {
      this.sort((a, b) {
        return b.percentTotalPoints.compareTo(a.percentTotalPoints);
      });
    }
  }

  void sortBySurname() {
    this.sort((a, b) {
      return a.shooter.lastName.compareTo(b.shooter.lastName);
    });
  }

  void sortByRating({required PreloadedRatingDataSource ratings, required RatingDisplayMode displayMode, required ShootingMatch match, MatchStage? stage}) {
    this.sort((a, b) {
      var aGroup = ratings.groupForDivisionSync(a.shooter.division);
      var bGroup = ratings.groupForDivisionSync(b.shooter.division);
      if(aGroup == null || bGroup == null) return b.ratio.compareTo(a.ratio);

      var aRating = ratings.lookupRatingSync(aGroup, a.shooter.memberNumber);
      var bRating = ratings.lookupRatingSync(bGroup, b.shooter.memberNumber);

      if(aRating == null || bRating == null) return b.ratio.compareTo(a.ratio);
      
      var settings = ratings.getSettingsSync();
      var aRatingWrapped = settings.algorithm.wrapDbRating(aRating);
      var bRatingWrapped = settings.algorithm.wrapDbRating(bRating);

      var aRatingValue = aRatingWrapped.ratingForEvent(match, stage);
      var bRatingValue = bRatingWrapped.ratingForEvent(match, stage);

      return bRatingValue.compareTo(aRatingValue);
    });
  }

  void sortByClassification() {
    this.sort((a, b) {
      return (a.shooter.classification?.index ?? 100000).compareTo(b.shooter.classification?.index ?? 100000);
    });
  }
}