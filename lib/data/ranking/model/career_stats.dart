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

var _log = SSALogger("CareerStats");

class CareerStats {
  Sport sport;
  ShooterRating rating;

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

  CareerStats(this.sport, this.rating) {
    _calculateAnnualStats();
  }

  late PeriodicStats careerStats;

  void _calculateAnnualStats() {
    annualStats = [];

    List<MatchHistoryEntry> matchHistory = rating.careerHistory();
    matchHistory.sort((a, b) => a.match.date.compareTo(b.match.date));
    DateTime earliest = matchHistory.first.match.date;
    DateTime latest = matchHistory.last.match.date;

    int firstYear = earliest.year;
    int lastYear = latest.year;
    years = List.generate(lastYear - firstYear + 1, (index) => firstYear + index);
    careerStats = PeriodicStats.container(career: this, start: earliest, end: latest, isCareer: true);

    for(int year in years) {
      DateTime yearStart = DateTime(year);
      DateTime yearEnd = DateTime(year + 1);

      var historyEntries = matchHistory.where((e) => e.match.date.isAfter(yearStart) && e.match.date.isBefore(yearEnd)).toList();
      var combinedEvents = rating.ratingEvents.where((e) => e.match.date.isAfter(yearStart) && e.match.date.isBefore(yearEnd)).toList();
      var stats = PeriodicStats(career: this, combinedEvents: combinedEvents, matchHistory: historyEntries, start: yearStart, end: yearEnd);
      annualStats.add(stats);
      careerStats.addFrom(stats);
    }

    careerStats.resort();
  }
}

class PeriodicStats {
  PeriodicStats({required this.career, required this.combinedEvents, required this.matchHistory, required this.start, required this.end, this.isCareer = false}) {
    this.events = combinedEvents.where((e) => e.ratingChange != 0).toList();
    calculateTotalScore();
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
    events.sort((a, b) => b.wrappedEvent.dateAndStageNumber.compareTo(a.wrappedEvent.dateAndStageNumber));
    combinedEvents.sort((a, b) => b.wrappedEvent.dateAndStageNumber.compareTo(a.wrappedEvent.dateAndStageNumber));
    matchHistory.sort((a, b) => a.match.date.compareTo(b.match.date));
  }


  void calculateTotalScore() {
    // scoring isn't important; we'll add to targetEvents/penaltyEvents later
    var total = RawScore(scoring: const HitFactorScoring(), targetEvents: {}, penaltyEvents: {});

    Map<ShootingMatch, RelativeMatchScore> matchScores = {};
    for(var event in combinedEvents) {
      var match = event.match;
      var divisions = rating.group.ipscCompatibleDivisions();
      RelativeScore eventScore;
      RelativeMatchScore? matchScore;
      if(matchScores.containsKey(match)) {
        matchScore = matchScores[match]!;
      }
      else {
        var scores = match.getScoresFromFilters(FilterSet(sport, divisions: divisions, empty: true, mode: FilterMode.or));
        matchScore = scores.entries.firstWhereOrNull((element) => rating.equalsShooter(element.key))?.value;
        if(matchScore == null) {
          _log.w("Shooter ${rating.name} doesn't have a score for match ${match.name}");
          continue;
        }
        matchScores[match] = matchScore;
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

        var stageClassScores = match.getScores(
          stages: [stage],
          shooters: match.shooters.where((element) =>
            eventScore.shooter.division == element.division
            && eventScore.shooter.classification == element.classification
          ).toList()
        );
        var stageClassScore = stageClassScores.entries.firstWhereOrNull((element) => rating.equalsShooter(element.key))?.value;

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
      if(eventScore.shooter.classification != null) {
        classesByMatch[event.match] = eventScore.shooter.classification!;
      }
      if(eventScore.shooter.division != null) {
        divisionsByMatch[event.match] = eventScore.shooter.division!;
      }

      // switch(score.shooter.powerFactor) {
      //   case old.PowerFactor.major:
      //     majorEntries += 1;
      //     break;
      //   case old.PowerFactor.minor:
      //     minorEntries += 1;
      //     break;
      //   default:
      //     otherEntries += 1;
      //     break;
      // }
    }

    totalScore = total;

    for(var match in matches) {
      var classification = classesByMatch[match];
      var division = divisionsByMatch[match]!;
      var scores = match.getScores(shooters: match.shooters.where((element) => element.division == division).toList());
      competitorCounts.add(scores.length);
      var score = scores.entries.firstWhereOrNull((element) => rating.equalsShooter(element.key))?.value;

      if(score == null) {
        throw StateError("Shooter in match doesn't have a score");
      }

      matchPlaces.add(score.place);
      matchPercentages.add(score.percentage);
      if (score.place == 1) matchWins += 1;

      if (classification != null) {
        var scores = match.getScores(
            shooters: match.shooters.where((element) => element.division == division && element.classification == classification).toList());
        var score = scores.entries.firstWhereOrNull((element) => rating.equalsShooter(element.key))!.value;

        if(!classification.fallback) {
          classMatchPlaces.add(score.place);
          classMatchPercentages.add(score.percentage);
          if (score.place == 1) {
            classMatchWins += 1;
          }
        }
      }
    }

  }
}
