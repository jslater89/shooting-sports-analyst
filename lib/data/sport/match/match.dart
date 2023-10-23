import 'package:isar/isar.dart';
import 'package:uspsa_result_viewer/data/match/practical_match.dart' as oldschema;
import 'package:uspsa_result_viewer/data/sport/match/translator.dart';
import 'package:uspsa_result_viewer/data/sport/scoring/scoring.dart';
import 'package:uspsa_result_viewer/data/sport/shooter/shooter.dart';
import 'package:uspsa_result_viewer/data/sport/sport.dart';
import 'package:uspsa_result_viewer/ui/result_page.dart';

/// A match in some shooting event.
class ShootingMatch {
  /// The identifier corresponding to this match in the local database.
  int? databaseId;

  /// The identifier or identifiers corresponding to this match in the
  /// source it came from.
  List<String> sourceIds;

  String eventName;
  String rawDate;
  DateTime date;
  MatchLevel? level;

  /// The sport whose rules govern this match.
  Sport sport;

  /// Stages in this match. For sports without stages,
  /// this will contain one pseudo-stage that includes
  /// the match scores.
  List<MatchStage> stages;

  /// Shooters in this match.
  List<MatchEntry> shooters;

  ShootingMatch({
    this.databaseId,
    this.sourceIds = const [],
    required this.eventName,
    required this.rawDate,
    required this.date,
    this.level,
    required this.sport,
    required this.stages,
    required this.shooters,
  });

  factory ShootingMatch.fromOldMatch(oldschema.PracticalMatch match) {
    return MatchTranslator.shootingMatchFrom(match);
  }

  Map<MatchEntry, RelativeMatchScore> getScores({
    List<MatchEntry>? shooters,
    List<MatchStage>? stages,
    bool scoreDQ = true,
    MatchPredictionMode predictionMode = MatchPredictionMode.none,
  }) {
    var innerShooters = shooters ?? this.shooters;
    var innerStages = stages ?? this.stages;

    return sport.matchScoring.calculateMatchScores(
      shooters: innerShooters,
      stages: innerStages,
      scoreDQ: scoreDQ,
      predictionMode: predictionMode
    );
  }
}

class MatchStage {
  int stageId;
  String name;

  /// The minimum number of scoring events required to
  /// complete this stage. In USPSA, for instance, this is
  /// the minimum number of rounds required to complete the stage:
  /// every shot will either be a hit, a miss, or a no-penalty miss.
  ///
  ///
  /// If it cannot be determined, or this is not a valid concept in the
  /// sport, use '0'. IDPA or ICORE parsed from Practiscore HTML, for example,
  /// would use '0', because we don't have stage information beyond raw time,
  /// points down, and penalties.
  ///
  /// In e.g. sporting clays, the minimum number of scoring events, if
  /// the scoring event is '1 bird', is 0.
  int minRounds;

  /// The maximum number of points available on this stage, or 0
  /// if 'maximum points' is not a valid concept in the sport.
  int maxPoints;

  bool classifier;
  String classifierNumber;
  StageScoring scoring;

  MatchStage({
    required this.stageId,
    required this.name,
    required this.scoring,
    this.minRounds = 0,
    this.maxPoints = 0,
    this.classifier = false,
    this.classifierNumber = "",
  });
}