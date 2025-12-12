/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:collection/collection.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:shooting_sports_analyst/data/source/match_source_error.dart';
import 'package:shooting_sports_analyst/data/sport/model.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/util.dart';

part 'classifier_import.g.dart';

final _log = SSALogger("ClassifierImporter");

/// ClassifierImporter takes JSON-encoded classifier scores as input, and outputs
/// [ShootingMatch]s.
///
/// Those matches are pseudo-matches, each containing all scores for a classifier
/// on all divisions with at least [minimumScoreCount] scores, grouped by [duration].
class ClassifierImporter {
  static const String sourceCode = "classifier-import";

  /// The sport of the classifier scores.
  Sport sport;

  /// The duration of each pseudo-match.
  PseudoMatchDuration duration;

  /// The number of scores required to include a division in
  /// each pseudo-match.
  int minimumScoreCount;

  /// The prefix to use for the pseudo-match names.
  String matchNamePrefix;

  ClassifierImporter({
    required this.sport,
    required this.duration,
    required this.minimumScoreCount,
    this.matchNamePrefix = "",
  });

  ClassifierImportResult import(List<ClassifierScore> scores) {
    Set<String> divisions = {};
    for(var score in scores) {
      divisions.add(score.division);
    }

    DateTime earliestDate = scores.first.date;
    DateTime latestDate = scores.first.date;
    Map<DateTime, List<ClassifierScore>> scoresByDate = {};
    for(var score in scores) {
      if(score.date.isBefore(earliestDate)) {
        earliestDate = score.date;
      }
      if(score.date.isAfter(latestDate)) {
        latestDate = score.date;
      }
      var roundedDate = duration == PseudoMatchDuration.month ? DateTime(score.date.year, score.date.month, 1) : DateTime(score.date.year, 1, 1);
      scoresByDate.addToList(roundedDate, score);
    }

    List<ShootingMatch> matches = [];
    // For each month, sort scores by classifier, then by division. If there
    // are enough scores for a pseudo-match in at least one division, create
    // a match for that classifier.
    for(var date in scoresByDate.keys) {
      var scores = scoresByDate[date]!;
      Map<String, List<ClassifierScore>> scoresByClassifier = {};

      // Group scores by classifier.
      for(var score in scores) {
        scoresByClassifier.addToList(score.classifierCode, score);
      }

      int pseudoDateOffset = 0;

      // For each classifier, group scores by division.
      for(var classifier in scoresByClassifier.keys) {
        var classifierScores = scoresByClassifier[classifier]!;
        Map<String, List<ClassifierScore>> scoresByDivision = {};
        int? classifierNumber;
        for(var score in classifierScores) {
          scoresByDivision.addToList(score.division, score);
          classifierNumber = score.classifierNumber;
        }

        // TODO: handle fixed-time classifiers
        // maybe at the ClassifierScore level?
        var stage = MatchStage(
          name: classifier,
          stageId: classifierNumber ?? 1,
          scoring: sport.defaultStageScoring,
          maxPoints: 80,
          minRounds: 16,
          classifier: true,
          classifierNumber: classifier
        );


        // If there are enough scores for a pseudo-match in at least one division,
        // add match entries/scores for that division.
        List<MatchEntry> entries = [];
        for(var division in divisions) {
          var divisionScores = scoresByDivision[division];
          if(divisionScores == null || divisionScores.length < minimumScoreCount) {
            continue;
          }

          entries.addAll(_createMatchEntryScores(stage, divisionScores, startingId: entries.length + 1));
        }

        // If there are any entries, create a match for the classifier.
        if(entries.isNotEmpty) {
          var pseudoDate = date.add(Duration(hours: pseudoDateOffset));
          pseudoDateOffset += 1;

          // The source-last-updated date is either the first day of the next month past the
          // match pseudo-date (if we're after the month in question), or the current date
          // if we're still within the month.
          DateTime sourceLastUpdated = DateTime(date.year, date.month + 1, 1);
          if(duration.containsDate(referenceDate: date, queryDate: DateTime.now())) {
            sourceLastUpdated = DateTime.now();
          }

          var match = ShootingMatch(
            name: "$matchNamePrefix $classifier ${programmerYmdFormat.format(date)}",
            rawDate: programmerYmdFormat.format(pseudoDate),
            date: pseudoDate,
            sport: sport,
            level: sport.eventLevels.values.firstWhereOrNull((e) => e.fallback),
            sourceLastUpdated: sourceLastUpdated,
            stages: [stage],
            shooters: entries,
            sourceCode: sourceCode,
            sourceIds: ["${sport.name}-${classifier}-${programmerYmdFormat.format(date)}"],
          );
          matches.add(match);
        }
      }
    }

    return Result.ok(matches);
  }

  /// Create match entries and scores for a division/classifier/date combo. Since
  /// our pseudo-matches are always single-stage, we don't need to worry about the
  /// bookkeeping of multiple stage scores per entry: each score in [scores]
  /// corresponds to a single entry in the pseudo-match.
  List<MatchEntry> _createMatchEntryScores(MatchStage stage,List<ClassifierScore> scores, {int startingId = 1}) {
    List<MatchEntry> entries = [];

    for(var score in scores) {
      var division = sport.divisions.lookupByName(score.division);
      if(division == null) {
        _log.w("Division not found: ${score.division}");
        continue;
      }

      var classification = sport.classifications.lookupByName(score.classification);
      if(classification == null) {
        _log.w("Classification not found: ${score.classification}");
      }

      // Create raw score
      var raw = RawScore(
        scoring: sport.defaultStageScoring,
        targetEvents: {},
        penaltyEvents: {},
        rawTime: score.time,
        dq: false,
      );

      // Create and add entry
      var entry = MatchEntry(
        entryId: startingId++,
        firstName: score.firstName,
        lastName: score.lastName,
        powerFactor: sport.defaultPowerFactor,
        scores: {stage: raw},
        division: division,
        classification: classification,
        memberNumber: score.memberNumber,
        reentry: false,
      );
      entries.add(entry);
    }

    return entries;
  }
}

typedef ClassifierImportResult = Result<List<ShootingMatch>, MatchSourceError>;

enum PseudoMatchDuration {
  month,
  year;

  // TODO: rather than containsDate, check for after reference date +1 period
  // I can't think of scenarios where we'd have a referenceDate in the future,
  // given that we're talking about existing scores, but the extra robustness
  // will make me feel better.

  bool containsDate({
    required DateTime referenceDate,
    required DateTime queryDate,
  }) {
    return switch(this) {
      month => referenceDate.month == queryDate.month && referenceDate.year == queryDate.year,
      year => referenceDate.year == queryDate.year,
    };
  }

  DateTime getReferenceDate(DateTime date) {
    return switch(this) {
      month => DateTime(date.year, date.month, 1),
      year => DateTime(date.year, 1, 1),
    };
  }
}

/// A classifier score is a single classifier stage score.
///
/// This class contains fields for scoring and penalty events, but in the event that
/// the classifier score data does not contain that information (i.e., if USPSA classifier
/// data has only time and points, or only hit factor), the converter implementation
/// should generate classifier scores that use artificial scoring/penalty events to
/// reproduce the known data.
@JsonSerializable()
class ClassifierScore {
  /// The unique identifier for the classifier.
  final String classifierCode;
  /// A numeric identifier for the classifier. If not provided in the constructor,
  /// it will be the hash of classifierCode mod 1000.
  final int classifierNumber;
  /// The date the score was achieved.
  final DateTime date;
  /// The division name in which the score was achieved.
  final String division;
  /// The competitor's first name.
  final String firstName;
  /// The competitor's last name.
  final String lastName;
  /// The competitor's member number/ID.
  final String memberNumber;
  /// The competitor's class (either at the time of the score, or now).
  String? classification;

  /// A synthetic sort property that matches RatingEvent sort order.
  int get dateAndStageNumber => date.millisecondsSinceEpoch ~/ 1000 + classifierNumber;

  /// A map of scoring event names to their counts.
  final Map<String, int> scoringEvents;
  /// A map of penalty event names to their counts.
  final Map<String, int> penaltyEvents;

  /// The time taken to complete the classifier stage.
  ///
  /// This is a pseudo-raw time: it may be the actual raw time
  /// or a semi-raw time, depending on the information available
  /// when creating the score. The final time will be calculated
  /// based on [time] and any bonuses or penalties in [scoringEvents]
  /// and [penaltyEvents].
  final double time;

  /// The number of points scored. The amount in this variable will
  /// be added to the score implied by [scoringEvents] and [penaltyEvents],
  /// and can be used as a shortcut if the data does not contain scoring
  /// events. The classifier importer will create dummy events to make up
  /// the difference.
  final int points;

  ClassifierScore({
    required this.classifierCode,
    int? classifierNumber,
    required this.date,
    required this.division,
    this.classification,
    required this.firstName,
    required this.lastName,
    required this.memberNumber,
    this.scoringEvents = const {},
    this.penaltyEvents = const {},
    this.time = 0.0,
    this.points = 0,
  }) : classifierNumber = classifierNumber ?? (classifierCode.stableHash % 1000);
  factory ClassifierScore.fromJson(Map<String, dynamic> json) => _$ClassifierScoreFromJson(json);
  Map<String, dynamic> toJson() => _$ClassifierScoreToJson(this);
}
