/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "package:collection/collection.dart";
import "package:shooting_sports_analyst/data/database/analyst_database.dart";
import "package:shooting_sports_analyst/data/database/match/rating_project_database.dart";
import "package:shooting_sports_analyst/data/database/schema/match.dart";
import "package:shooting_sports_analyst/data/database/schema/ratings/db_rating_event.dart";
import "package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart";
import "package:shooting_sports_analyst/data/sport/builtins/registry.dart";
import "package:shooting_sports_analyst/data/sport/scoring/scoring.dart";
import "package:shooting_sports_analyst/data/sport/sport.dart";
import "package:shooting_sports_analyst/logger.dart";
import "package:shooting_sports_analyst/util.dart";

final _log = SSALogger("CheapCareerStats");

/// Career statistics from stored match-entry fields, without hydrating matches
/// or recalculating scores.
///
/// Uses each entry's [DbMatchEntryBase.precalculatedScore] (per-division place
/// and stage places written at save time) and hydrates only that entry's
/// [DbRawScore]s for hit totals, time, and points.
///
/// These totals will disagree with full [CareerStats] where that type rescores
/// the rating group's divisions (plus sport-link inbound divisions) and class,
/// and where a by-stage rating only counts stages that produced a rating event.
class CheapCareerStats {
  CheapCareerStats(this.rating) : sport = rating.sport {
    _calculateSync();
  }

  CheapCareerStats._(this.rating) : sport = rating.sport;

  /// Async constructor for worker isolates. Awaits each match (and separately
  /// stored shooter links) so the event loop can handle other requests between
  /// matches. Does not call synchronous database methods.
  static Future<CheapCareerStats> load(ShooterRating rating) async {
    final stats = CheapCareerStats._(rating);
    await stats._calculateAsync();
    return stats;
  }

  final ShooterRating rating;
  final Sport sport;

  late CheapPeriodicStats careerStats;
  List<CheapPeriodicStats> annualStats = [];
  List<int> years = [];

  /// Matches referenced by rating events that were not found in the database.
  int missingMatches = 0;

  /// Matches where the entry had no usable [DbMatchEntryBase.precalculatedScore]
  /// (place 0 / empty).
  int unscoredMatches = 0;

  /// Get the periodic statistics for the given year. If year is 0, return the
  /// career statistics.
  CheapPeriodicStats? statsForYear(int year) {
    if(year == 0) {
      return careerStats;
    }
    return annualStats.firstWhereOrNull((e) => e.start.year == year);
  }

  void _calculateSync() {
    final totalSw = Stopwatch()..start();
    final db = AnalystDatabase();

    final loadSw = Stopwatch()..start();
    final visits = _dedupeVisitsFromRatingEvents(rating.ratingEvents.map((e) => e.wrappedEvent));
    loadSw.stop();
    _log.v("ratingEvents load+dedupe: ${loadSw.elapsedMilliseconds}ms (${visits.length} matches)");

    final foldSw = Stopwatch()..start();
    final byYear = <int, CheapPeriodicStats>{};
    for(final visit in visits) {
      final match = db.getMatchByAnySourceIdSync([visit.matchId]);
      if(match == null) {
        missingMatches += 1;
        continue;
      }
      if(match.shootersStoredSeparately && !match.shooterLinks.isLoaded) {
        match.shooterLinks.loadSync();
      }
      final shooters = _shootersOf(match);
      _foldVisit(byYear, visit: visit, match: match, shooters: shooters);
    }
    foldSw.stop();
    _log.v("sync fold: ${foldSw.elapsedMilliseconds}ms "
        "(missing=$missingMatches, unscored=$unscoredMatches)");

    _finalizeFromYears(byYear);
    _log.v("_calculateSync total: ${totalSw.elapsedMilliseconds}ms "
        "(matches=${visits.length}, years=${years.length})");
  }

  Future<void> _calculateAsync() async {
    final totalSw = Stopwatch()..start();
    final db = AnalystDatabase();

    final loadSw = Stopwatch()..start();
    final persisted = await db.getRatingEventsFor(rating.wrappedRating);
    final events = [
      ...persisted,
      ...rating.wrappedRating.newRatingEvents,
    ];
    final visits = _dedupeVisitsFromRatingEvents(events);
    loadSw.stop();
    _log.v("async ratingEvents load+dedupe: ${loadSw.elapsedMilliseconds}ms (${visits.length} matches)");

    final foldSw = Stopwatch()..start();
    final byYear = <int, CheapPeriodicStats>{};
    for(final visit in visits) {
      final match = await db.getMatchBySourceId(visit.matchId);
      if(match == null) {
        missingMatches += 1;
        continue;
      }
      if(match.shootersStoredSeparately && !match.shooterLinks.isLoaded) {
        await match.shooterLinks.load();
      }
      final shooters = _shootersOf(match);
      _foldVisit(byYear, visit: visit, match: match, shooters: shooters);
    }
    foldSw.stop();
    _log.v("async fold: ${foldSw.elapsedMilliseconds}ms "
        "(missing=$missingMatches, unscored=$unscoredMatches)");

    _finalizeFromYears(byYear);
    _log.v("_calculateAsync total: ${totalSw.elapsedMilliseconds}ms "
        "(matches=${visits.length}, years=${years.length})");
  }

  List<_MatchVisit> _dedupeVisitsFromRatingEvents(Iterable<DbRatingEvent> events) {
    final seen = <String>{};
    final visits = <_MatchVisit>[];
    for(final e in events) {
      if(!seen.add(e.matchId)) {
        continue;
      }
      visits.add(_MatchVisit(matchId: e.matchId, entryId: e.entryId, date: e.date));
    }
    visits.sort((a, b) => a.date.compareTo(b.date));
    return visits;
  }

  List<DbMatchEntryBase> _shootersOf(DbShootingMatch match) {
    if(match.shootersStoredSeparately) {
      return match.shooterLinks.toList();
    }
    return match.shooters;
  }

  void _foldVisit(
    Map<int, CheapPeriodicStats> byYear, {
    required _MatchVisit visit,
    required DbShootingMatch match,
    required List<DbMatchEntryBase> shooters,
  }) {
    final year = visit.date.year;
    final period = byYear.putIfAbsent(year, () => CheapPeriodicStats(
      start: DateTime(year),
      end: DateTime(year + 1).add(const Duration(seconds: -1)),
    ));
    final folded = _foldMatch(period, match: match, shooters: shooters, entryId: visit.entryId);
    if(!folded) {
      unscoredMatches += 1;
    }
  }

  /// Returns false when the entry is missing or has no usable precalculated score.
  bool _foldMatch(
    CheapPeriodicStats period, {
    required DbShootingMatch match,
    required List<DbMatchEntryBase> shooters,
    required int entryId,
  }) {
    final entry = shooters.firstWhereOrNull((s) => s.entryId == entryId);
    if(entry == null) {
      _log.w("Entry $entryId not found in ${match.eventName}");
      return false;
    }

    final score = entry.precalculatedScore;
    // place 0 means the score was never written. ratio 0 is a stored no-score
    // (subminor / DNF) that still has an ordinal place and must not fold in.
    if(score == null || score.place == 0 || score.ratio == 0) {
      _log.w("No usable precalculated score for entry $entryId in ${match.eventName} "
          "(place=${score?.place}, ratio=${score?.ratio})");
      return false;
    }

    period.matchCount += 1;
    period.matchPlaces.add(score.place);
    period.matchPercentages.add(score.percentage);
    if(score.place == 1) {
      period.matchWins += 1;
    }

    for(final stageScore in score.stageScores) {
      if(stageScore.place == 0) {
        continue;
      }
      period.stageFinishes.add(stageScore.place);
      period.stagePercentages.add(stageScore.percentage);
      if(stageScore.place == 1) {
        period.stageWins += 1;
      }
    }

    final raw = _hydrateEntryScores(match, entry);
    if(raw != null) {
      if(period.totalScore == null) {
        period.totalScore = raw;
      }
      else {
        period.totalScore = period.totalScore! + raw;
      }
      period.totalPoints += raw.points.toDouble();
    }

    if(entry.dq) {
      period.dqCount += 1;
    }

    period.matchesByLevel.increment(match.matchEventLevel);

    final divisionName = entry.divisionName;
    if(divisionName != null) {
      final competitors = shooters.where((s) =>
        !s.reentry && s.divisionName == divisionName
      ).length;
      period.competitorCounts.add(competitors);
    }

    return true;
  }

  RawScore? _hydrateEntryScores(DbShootingMatch match, DbMatchEntryBase entry) {
    final matchSport = SportRegistry().lookup(match.sportName) ?? sport;
    final pf = matchSport.powerFactors.lookupByName(entry.powerFactorName)
        ?? matchSport.defaultPowerFactor;
    final stagesById = {
      for(final s in match.stages) s.stageId: s.hydrate(matchSport),
    };
    final localBonus = match.localBonusEvents.map((e) => e.toScoringEvent()).toList();
    final localPenalty = match.localPenaltyEvents.map((e) => e.toScoringEvent()).toList();

    RawScore? total;
    for(final dbScore in entry.scores) {
      final stage = stagesById[dbScore.stageId];
      if(stage == null) {
        continue;
      }
      final hydrated = dbScore.hydrate(stage, pf, localBonus, localPenalty);
      if(hydrated.isErr()) {
        continue;
      }
      final raw = hydrated.unwrap();
      if(total == null) {
        total = raw;
      }
      else {
        total = total + raw;
      }
    }
    return total;
  }

  void _finalizeFromYears(Map<int, CheapPeriodicStats> byYear) {
    annualStats = [];
    years = byYear.keys.toList()..sort();

    if(years.isEmpty) {
      final now = DateTime.now();
      careerStats = CheapPeriodicStats(start: now, end: now, isCareer: true);
      return;
    }

    careerStats = CheapPeriodicStats(
      start: DateTime(years.first),
      end: DateTime(years.last + 1).add(const Duration(seconds: -1)),
      isCareer: true,
    );
    for(final year in years) {
      final stats = byYear[year]!;
      annualStats.add(stats);
      careerStats.addFrom(stats);
    }
  }
}

class CheapPeriodicStats {
  CheapPeriodicStats({
    required this.start,
    required this.end,
    this.isCareer = false,
  });

  final bool isCareer;
  final DateTime start;
  final DateTime end;

  int matchCount = 0;
  int matchWins = 0;
  List<int> matchPlaces = [];
  List<double> matchPercentages = [];

  int stageWins = 0;
  List<int> stageFinishes = [];
  List<double> stagePercentages = [];

  RawScore? totalScore;
  double totalPoints = 0;
  int dqCount = 0;
  Map<EventLevel, int> matchesByLevel = {};
  List<int> competitorCounts = [];

  int get stageCount => stageFinishes.length;

  double? get averageMatchPlace =>
      matchPlaces.isEmpty ? null : matchPlaces.average;
  double? get averageMatchPercentage =>
      matchPercentages.isEmpty ? null : matchPercentages.average;
  double? get averageStagePlace =>
      stageFinishes.isEmpty ? null : stageFinishes.average;
  double? get averageStagePercentage =>
      stagePercentages.isEmpty ? null : stagePercentages.average;
  double? get averageCompetitors =>
      competitorCounts.isEmpty ? null : competitorCounts.average;

  Map<String, int> hitCountsByName() {
    final score = totalScore;
    if(score == null) {
      return {};
    }
    final counts = <String, int>{};
    for(final entry in score.targetEvents.entries) {
      // Name only: Major C (4pt) and Minor C (3pt) share a bucket.
      counts.incrementBy(entry.key.name, entry.value);
    }
    return counts;
  }

  /// Hit percentages keyed by scoring-event name, using name-bucketed counts.
  ///
  /// Do not derive this from [RawScore.hitPercentages]: [ScoringEvent] equality
  /// includes point value, so Major/Minor (or subminor) variants of the same
  /// letter stay as separate keys and a name-keyed map overwrites one with the
  /// other.
  Map<String, double> hitPercentagesByName() {
    final counts = hitCountsByName();
    final total = counts.values.fold<int>(0, (a, b) => a + b);
    if(total == 0) {
      return {};
    }
    return {
      for(final e in counts.entries) e.key: e.value / total,
    };
  }

  void addFrom(CheapPeriodicStats other) {
    if(totalScore == null && other.totalScore != null) {
      totalScore = other.totalScore!.copy();
    }
    else if(totalScore == null && other.totalScore == null) {
      totalScore = RawScore(scoring: const HitFactorScoring(), targetEvents: {}, penaltyEvents: {});
    }
    else if(other.totalScore != null) {
      totalScore = totalScore! + other.totalScore!;
    }

    totalPoints += other.totalPoints;
    matchCount += other.matchCount;
    matchWins += other.matchWins;
    matchPlaces.addAll(other.matchPlaces);
    matchPercentages.addAll(other.matchPercentages);

    stageWins += other.stageWins;
    stageFinishes.addAll(other.stageFinishes);
    stagePercentages.addAll(other.stagePercentages);

    dqCount += other.dqCount;
    competitorCounts.addAll(other.competitorCounts);

    for(final entry in other.matchesByLevel.entries) {
      matchesByLevel.incrementBy(entry.key, entry.value);
    }
  }
}

class _MatchVisit {
  _MatchVisit({
    required this.matchId,
    required this.entryId,
    required this.date,
  });

  final String matchId;
  final int entryId;
  final DateTime date;
}
