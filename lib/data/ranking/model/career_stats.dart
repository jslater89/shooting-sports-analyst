/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:collection/collection.dart';
import 'package:shooting_sports_analyst/data/ranking/rater_types.dart';
import 'package:shooting_sports_analyst/data/sport/model.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/filter_set.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/util.dart';

var _log = SSALogger("CareerStats");

class CareerStats {
  Sport sport;
  ShooterRating rating;
  CareerStatsMatchScoreCache matchScoreCache = CareerStatsMatchScoreCache();

  List<PeriodicStats> annualStats = [];
  bool get byStage => annualStats.any((e) => e.byStage);

  List<int> years = [];

  /// Get the periodic statistics for the given year. If year is 0,
  /// return the career statistics.
  PeriodicStats? statsForYear(int year) {
    if(year == 0) {
      // I was going to say that this would break ratings for Roman
      // charioteers around the BC/AD change, but of course there was no
      // year zero, so we're good.
      return careerStats;
    }
    return annualStats.firstWhereOrNull((e) => e.start.year == year);
  }

  bool isAnnualStats(PeriodicStats stats) {
    return stats.start.year == stats.end.year;
  }

  CareerStats(this.sport, this.rating) {
    _calculateAnnualStats();
  }

  late PeriodicStats careerStats;

  void _calculateAnnualStats() {
    final totalSw = Stopwatch()..start();
    annualStats = [];

    final historySw = Stopwatch()..start();
    List<MatchHistoryEntry> matchHistory = rating.careerHistory(matchScoreCache: matchScoreCache, divisions: rating.group.ipscCompatibleDivisions());
    matchHistory.sort((a, b) => a.match.date.compareTo(b.match.date));
    historySw.stop();
    _log.v("careerHistory: ${historySw.elapsedMilliseconds}ms (${matchHistory.length} matches)");

    if(matchHistory.isEmpty) {
      careerStats = PeriodicStats.container(career: this, start: DateTime.now(), end: DateTime.now(), isCareer: true);
      _log.v("_calculateAnnualStats total: ${totalSw.elapsedMilliseconds}ms (empty)");
      return;
    }

    DateTime earliest = matchHistory.first.match.date;
    DateTime latest = matchHistory.last.match.date;

    int firstYear = earliest.year;
    int lastYear = latest.year;
    years = List.generate(lastYear - firstYear + 1, (index) => firstYear + index);
    careerStats = PeriodicStats.container(career: this, start: earliest, end: latest, isCareer: true);

    final yearsSw = Stopwatch()..start();
    var filterMs = 0;
    var scoreMs = 0;
    var resortMs = 0;
    for(int year in years) {
      DateTime yearStart = DateTime(year);
      // 1 second before the start of the next year
      DateTime yearEnd = DateTime(year + 1).add(Duration(seconds: -1));

      final filterSw = Stopwatch()..start();
      var historyEntries = matchHistory.where((e) => e.match.date.isAfter(yearStart) && e.match.date.isBefore(yearEnd)).toList();
      var combinedEvents = rating.ratingEvents.where((e) => e.match.date.isAfter(yearStart) && e.match.date.isBefore(yearEnd)).toList();
      filterMs += filterSw.elapsedMilliseconds;

      final scoreSw = Stopwatch()..start();
      var stats = PeriodicStats(career: this, combinedEvents: combinedEvents, matchHistory: historyEntries, start: yearStart, end: yearEnd);
      scoreMs += scoreSw.elapsedMilliseconds;

      // Resort here because we're sorting slightly differently than the DB sorts at the moment
      final resortSw = Stopwatch()..start();
      stats.resort();
      resortMs += resortSw.elapsedMilliseconds;
      annualStats.add(stats);
      careerStats.addFrom(stats);
    }
    yearsSw.stop();
    _log.v("annual PeriodicStats loop: ${yearsSw.elapsedMilliseconds}ms "
        "(filter ${filterMs}ms, calculateTotalScore ${scoreMs}ms, resort ${resortMs}ms; ${years.length} years)");

    final careerResortSw = Stopwatch()..start();
    careerStats.resort();
    _log.v("careerStats.resort: ${careerResortSw.elapsedMilliseconds}ms");

    _log.v("Match score cache: $matchScoreCache");
    _log.v("_calculateAnnualStats total: ${totalSw.elapsedMilliseconds}ms "
        "(events=${rating.ratingEvents.length}, matches=${matchHistory.length}, years=${years.length})");
  }
}

class PeriodicStats {
  PeriodicStats({required this.career, required this.combinedEvents, required this.matchHistory, required this.start, required this.end, this.isCareer = false}) {
    this.events = combinedEvents.where((e) => e.ratingChange != 0).toList();
    calculateTotalScore(career.matchScoreCache);
  }

  PeriodicStats.container({required this.career, required this.start, required this.end, this.isCareer = false});

  bool isCareer;

  CareerStats career;
  DateTime start;
  DateTime end;
  Sport get sport => career.sport;
  ShooterRating get rating => career.rating;
  List<RatingEvent> events = [];
  List<RatingEvent> combinedEvents = [];
  bool get byStage => events.isEmpty ? true : events.any((e) => e.stage != null);

  List<MatchHistoryEntry> matchHistory = [];
  RawScore? totalScore;
  double totalPoints = 0;
  Set<ShootingMatch> dqs = {};
  Set<ShootingMatch> matches = {};
  Map<ShootingMatch, Classification> classesByMatch = {};
  Map<ShootingMatch, Division> divisionsByMatch = {};
  Set<ShootingMatch> matchesWithRatingChanges = {};
  Map<MatchLevel, int> matchesByLevel = {};
  int majorEntries = 0;
  int minorEntries = 0;
  int otherEntries = 0;
  int get totalEntries => majorEntries + minorEntries + otherEntries;
  int stageWins = 0;
  List<int> stageFinishes = [];
  List<double> stagePercentages = [];
  int classStageWins = 0;
  List<int> classStageFinishes = [];
  List<double> classStagePercentages = [];
  int matchWins = 0;
  List<int> matchPlaces = [];
  List<double> matchPercentages = [];
  int classMatchWins = 0;
  List<int> classMatchPlaces = [];
  List<double> classMatchPercentages = [];
  List<int> competitorCounts = [];

  void addFrom(PeriodicStats other) {
    if(totalScore == null && other.totalScore != null) {
      totalScore = other.totalScore!.copy();
    }
    else if(totalScore == null && other.totalScore == null) {
      totalScore = RawScore(scoring: const HitFactorScoring(), targetEvents: {}, penaltyEvents: {});
    }
    else {
      totalScore = totalScore! + other.totalScore!;
    }

    events.addAll(other.events);
    combinedEvents.addAll(other.combinedEvents);
    matchHistory.addAll(other.matchHistory);

    totalPoints += other.totalPoints;
    matches.addAll(other.matches);
    dqs.addAll(other.dqs);
    classesByMatch.addAll(other.classesByMatch);
    divisionsByMatch.addAll(other.divisionsByMatch);
    matchesWithRatingChanges.addAll(other.matchesWithRatingChanges);
    matchesByLevel.addAll(other.matchesByLevel);

    majorEntries += other.majorEntries;
    minorEntries += other.minorEntries;
    otherEntries += other.otherEntries;

    stageWins += other.stageWins;
    stageFinishes.addAll(other.stageFinishes);
    stagePercentages.addAll(other.stagePercentages);

    classStageWins += other.classStageWins;
    classStageFinishes.addAll(other.classStageFinishes);
    classStagePercentages.addAll(other.classStagePercentages);

    matchWins += other.matchWins;
    matchPlaces.addAll(other.matchPlaces);
    matchPercentages.addAll(other.matchPercentages);

    classMatchWins += other.classMatchWins;
    classMatchPlaces.addAll(other.classMatchPlaces);
    classMatchPercentages.addAll(other.classMatchPercentages);

    competitorCounts.addAll(other.competitorCounts);
  }

  void resort() {
    events.sort((a, b) {
      if(b.wrappedEvent.date == a.wrappedEvent.date) {
        // For events on the same day but not the same match, we want to sort by match name
        if(a.wrappedEvent.matchId != b.wrappedEvent.matchId) {
          var aName = a.wrappedEvent.getMatchSync()?.eventName ?? "null";
          var bName = b.wrappedEvent.getMatchSync()?.eventName ?? "null";
          return aName.compareTo(bName);
        }
      }
      return b.wrappedEvent.dateAndStageNumber.compareTo(a.wrappedEvent.dateAndStageNumber);
    });
    combinedEvents.sort((a, b) {
      if(b.wrappedEvent.date == a.wrappedEvent.date) {
        // For events on the same day but not the same match, we want to sort by match name
        if(a.wrappedEvent.matchId != b.wrappedEvent.matchId) {
          var aName = a.wrappedEvent.getMatchSync()?.eventName ?? "null";
          var bName = b.wrappedEvent.getMatchSync()?.eventName ?? "null";
          return aName.compareTo(bName);
        }
      }
      return b.wrappedEvent.dateAndStageNumber.compareTo(a.wrappedEvent.dateAndStageNumber);
    });
    matchHistory.sort((a, b) {
      var result = a.match.date.compareTo(b.match.date);
      if(result != 0) {
        return result;
      }
      else {
        // Sort matches on the same day by name
        var aName = a.match.name;
        var bName = b.match.name;
        return bName.compareTo(aName);
      }
    });
  }


  void calculateTotalScore(CareerStatsMatchScoreCache matchScoreCache) {
    // scoring isn't important; we'll add to targetEvents/penaltyEvents later
    var total = RawScore(scoring: const HitFactorScoring(), targetEvents: {}, penaltyEvents: {});

    Map<String, bool> countedMatchResults = {};

    for(var event in combinedEvents) {
      var match = event.match;
      var divisions = rating.group.ipscCompatibleDivisions();
      RelativeScore eventScore;

      // We need a match score
      RelativeMatchScore? matchScore;
      RelativeMatchScore? classMatchScore;

      matchScore = matchScoreCache.getScore(match, divisions, null);
      if(matchScore == null) {
        var scores = match.getScoresFromFilters(FilterSet(sport, divisions: divisions, empty: true, mode: FilterMode.or));
        matchScore = scores.entries.firstWhereOrNull((element) => rating.equalsShooter(element.key))?.value;
        if(matchScore == null) {
          _log.w("Shooter ${rating.name} doesn't have a score for match ${match.name}");
          continue;
        }
        matchScoreCache.setScore(match, divisions, null, matchScore);
      }

      classMatchScore = matchScoreCache.getScore(match, divisions, matchScore.shooter.classification);
      if(classMatchScore == null) {
        var stageClassScores = match.getScores(
          shooters: match.shooters.where((element) =>
            matchScore!.shooter.division == element.division
            && matchScore.shooter.classification == element.classification
          ).toList()
        );
        classMatchScore = stageClassScores.entries.firstWhereOrNull((element) => rating.equalsShooter(element.key))?.value;
        if(classMatchScore == null) {
          _log.w("Shooter ${rating.name} doesn't have a score for class ${matchScore.shooter.classification!.name} in match ${match.name}");
          continue;
        }
        matchScoreCache.setScore(match, divisions, matchScore.shooter.classification!, classMatchScore);
      }

      if(byStage) {
        var stage = match.stages.firstWhereOrNull((s) => s.stageId == event.stageNumber);
        if(stage == null) {
          _log.w("${match.name} is missing stage ${event.stageNumber}");
          _log.vv("Has stages: ${match.stages.map((e) => "${e.stageId}: ${e.name}").toList()}");
          continue;
        }
        var stageScore = matchScore.stageScores[stage];
        if(stageScore == null) {
          _log.w("Shooter ${rating.name} doesn't have a score for stage ${stage.name} in match ${match.name}");
          continue;
        }
        eventScore = stageScore;

        if(eventScore.place == 1) {
          stageWins += 1;
        }
        stageFinishes.add(eventScore.place);
        stagePercentages.add(eventScore.percentage);

        final stageClassScore = classMatchScore.stageScores[stage];
        if(stageClassScore != null) {
        classStageFinishes.add(stageClassScore.place);
          classStagePercentages.add(stageClassScore.percentage);
          if (stageClassScore.place == 1) {
            classStageWins += 1;
          }
        }
      }
      else {
        eventScore = matchScore;
      }

      if(eventScore is RelativeMatchScore) {
        total += eventScore.total;
        totalPoints += eventScore.total.points;
      }
      else if(eventScore is RelativeStageScore) {
        total += eventScore.score;
        totalPoints += eventScore.score.points;
      }

      if(eventScore.shooter.dq) {
        dqs.add(event.match);
      }
      if(events.contains(event)) {
        matchesWithRatingChanges.add(event.match);
      }
      if(!matches.contains(event.match) && event.match.level != null) {
        matchesByLevel[event.match.level!] ??= 0;
        matchesByLevel[event.match.level!] = matchesByLevel[event.match.level!]! + 1;
      }
      matches.add(event.match);

      final matchClassification = eventScore.shooter.classification;

      if(!countedMatchResults.containsKey(event.match.sourceIds.first)) {
        countedMatchResults[event.match.sourceIds.first] = true;

        final divisionEntrants = match.filterShooters(
          filterMode: FilterMode.or,
          divisions: divisions,
        );
        competitorCounts.add(divisionEntrants.length);

        matchPlaces.add(matchScore.place);
        matchPercentages.add(matchScore.percentage);
        if (matchScore.place == 1) matchWins += 1;

        if (matchClassification != null) {
          if(!matchClassification.fallback) {
            classMatchPlaces.add(classMatchScore.place);
            classMatchPercentages.add(classMatchScore.percentage);
            if (classMatchScore.place == 1) {
              classMatchWins += 1;
            }
          }
        }
      }
    }

    totalScore = total;
  }
}

extension HitPercentagesText on RawScore {
  Map<ScoringEvent, double> hitPercentages(Sport sport) {
    Map<ScoringEvent, double> result = {};
    var totalCount = this.targetEventCount;
    var sortedEvents = this.targetEvents.entries.sorted((a, b) => a.key.sortOrder.compareTo(b.key.sortOrder));
    for(var entry in sortedEvents) {
      var event = entry.key;
      var count = entry.value;
      result[event] = count / totalCount;
    }
    return result;
  }

  String hitPercentagesText(Sport sport, {bool bestOnly = false}) {
    List<String> entries = [];
    var totalCount = this.targetEventCount;
    Map<String, int> eventCountsByName = {};
    var sortedEvents = this.targetEvents.entries.sorted((a, b) => a.key.sortOrder.compareTo(b.key.sortOrder));
    for(var entry in sortedEvents) {
      var event = entry.key;
      var count = entry.value;
      eventCountsByName.incrementBy(event.name, count);
    }

    var powerFactor = sport.defaultPowerFactor;
    for(var entry in eventCountsByName.entries) {
      var event = powerFactor.targetEvents.lookupByName(entry.key);
      if(event != null && event.displayInOverview) {
        entries.add("${(entry.value / totalCount).asPercentage(decimals: 1)} ${event.shortDisplayName}");
        if(bestOnly) {
          break;
        }
      }
    }

    return entries.join(", ");
  }

  String scoringEventText(Sport sport) {
    var message = StringBuffer();
    Map<String, int> eventCountsByName = {};
    var sortedEvents = this.targetEvents.entries.sorted((a, b) => a.key.sortOrder.compareTo(b.key.sortOrder));
    for(var entry in sortedEvents) {
      var event = entry.key;
      var count = entry.value;
      eventCountsByName.incrementBy(event.name, count);
    }

    var powerFactor = sport.defaultPowerFactor;
    for(var entry in eventCountsByName.entries) {
      var event = powerFactor.targetEvents.lookupByName(entry.key);
      var count = entry.value;
      if(event != null && event.displayInOverview) {
        if(sport.displaySettings.eventNamesAsSuffix) {
          message.write("$count${event.shortDisplayName} ");
        }
        else {
          message.write("${event.shortDisplayName}: $count ");
        }
      }
    }

    return message.toString();
  }
}

class CareerStatsMatchScoreCache {
  int _hits = 0;
  int _misses = 0;
  Map<CareerStatsMatchScoreCacheKey, RelativeMatchScore> scores = {};

  RelativeMatchScore? getScore(ShootingMatch match, List<Division> divisions, Classification? classification) {
    var key = CareerStatsMatchScoreCacheKey(matchId: match.sourceIds.first, divisionIds: divisions.map((e) => e.name).toList(), classification: classification);
    var score = scores[key];
    if(score != null) {
      _hits += 1;
      return score;
    }
    else {
      _misses += 1;
      return null;
    }
  }

  void setScore(ShootingMatch match, List<Division> divisions, Classification? classification, RelativeMatchScore score) {
    var key = CareerStatsMatchScoreCacheKey(matchId: match.sourceIds.first, divisionIds: divisions.map((e) => e.name).toList(), classification: classification);
    scores[key] = score;
  }

  String toString() => "CareerStatsMatchScoreCache(hits: $_hits, misses: $_misses, scores: ${scores.length})";
}

class CareerStatsMatchScoreCacheKey {
  String matchId;
  List<String> divisionIds;
  Classification? classification;

  CareerStatsMatchScoreCacheKey({required this.matchId, required this.divisionIds, required this.classification});

  operator ==(Object other) {
    if(other is CareerStatsMatchScoreCacheKey) {
      return matchId == other.matchId &&
        divisionIds.intersection(other.divisionIds).length == divisionIds.length && divisionIds.length == other.divisionIds.length &&
        classification == other.classification;
    }
    return false;
  }

  int get hashCode => combineHashList64([matchId.hashCode, combineHashList64(divisionIds.sorted().map((e) => e.hashCode).toList()), classification?.hashCode ?? 0]);

  String toString() => "CareerStatsMatchScoreCacheKey(matchId: $matchId, divisionIds: $divisionIds, classification: $classification)";
}