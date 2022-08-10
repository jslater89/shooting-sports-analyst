import 'package:flutter/foundation.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:intl/intl.dart';

const verboseParse = false;

Future<PracticalMatch> processScoreFile(String fileContents) async {
  String reportFile = fileContents.replaceAll("\r\n", "\n");
  List<String> lines = reportFile.split("\n");

  List<String> infoLines = [];
  List<String> competitorLines = [];
  List<String> stageLines = [];
  List<String> stageScoreLines = [];

  for (String l in lines) {
    l = l.trim();
    if (l.startsWith(r"$INFO"))
      infoLines.add(l);
    else if (l.startsWith("E "))
      competitorLines.add(l);
    else if (l.startsWith("G "))
      stageLines.add(l);
    else if (l.startsWith("I "))
      stageScoreLines.add(l);
  }

  PracticalMatch canonicalMatch = _processResultLines(
    infoLines: infoLines,
    competitorLines: competitorLines,
    stageLines: stageLines,
    stageScoreLines: stageScoreLines,
  )..reportContents = reportFile;
  return canonicalMatch;
}

PracticalMatch _processResultLines({required List<String> infoLines, required List<String> competitorLines, required List<String> stageLines, required List<String> stageScoreLines}) {
  PracticalMatch match = PracticalMatch();
  _readInfoLines(match, infoLines);

  Map<int, Shooter> shootersByFileId = _readCompetitorLines(match, competitorLines);
  Map<int, Stage> stagesByFileId = _readStageLines(match, stageLines);

  int stageScoreCount = _readScoreLines(stageScoreLines, shootersByFileId, stagesByFileId);

  for(Shooter s in match.shooters) {
    for(Stage stage in match.stages) {
      if(!s.stageScores.containsKey(stage)) {
        s.stageScores[stage] = Score(shooter: s)..stage = stage;
      }
    }
  }

  debugPrint("Processed match ${match.name} with ${match.shooters.length} shooters, ${match.stages.length} stages, and $stageScoreCount stage scores");

  return match;
}

const String _MATCH_NAME = r"$INFO Match name:";
const String _MATCH_DATE = r"$INFO Match date:";
const String _MATCH_LEVEL = r"$INFO Match Level:";
final DateFormat _df = DateFormat("MM/dd/yyyy");

void _readInfoLines(PracticalMatch match, List<String> infoLines) {
  for(String line in infoLines) {
    if(line.startsWith(_MATCH_NAME)) {
      // debugPrint("Found match name");
      match.name = line.replaceFirst(_MATCH_NAME, "");
    }
    else if(line.startsWith(_MATCH_DATE)) {
      // debugPrint("Found match date");
      match.rawDate = line.replaceFirst(_MATCH_DATE, "");
      try {
        match.date = _df.parse(match.rawDate!);
      }
      catch(e) {
        debugPrint("Unable to parse date ${match.rawDate} $e");
      }
    }
    else if(line.startsWith(_MATCH_LEVEL)) {
      var level = line.replaceFirst(_MATCH_LEVEL, "").toUpperCase();
      if(level.contains("IV")) match.level = MatchLevel.IV;
      else if(level.contains("III")) match.level = MatchLevel.III;
      else if(level.contains("II")) match.level = MatchLevel.II;
      else if(level.contains("I")) match.level = MatchLevel.I;

      // debugPrint("${match.name} has $level => ${match.level}");
    }
  }
}

const int _MEMBER_NUM = 1;
const int _FIRST_NAME = 2;
const int _LAST_NAME = 3;
const int _DQ_PISTOL = 4;
const int _DQ_RIFLE = 5;
const int _DQ_SHOTGUN = 6;
const int _REENTRY = 7;
const int _CLASS = 8;
const int _DIVISION = 9;
const int _POWER_FACTOR = 12;
Map<int, Shooter> _readCompetitorLines(PracticalMatch match, List<String> competitorLines) {
  Map<int, Shooter> shootersById = {};

  int i = 1;
  for(String line in competitorLines) {
    try {
      List<String> splitLine = line.split(",");
      Shooter s = Shooter()
        ..memberNumber = splitLine[_MEMBER_NUM]
        ..firstName = splitLine[_FIRST_NAME]
        ..lastName = splitLine[_LAST_NAME]
        ..reentry = splitLine[_REENTRY].toLowerCase() == "yes"
        ..classification = ClassificationFrom.string(splitLine[_CLASS])
        ..division = DivisionFrom.string(splitLine[_DIVISION])
        ..powerFactor = PowerFactorFrom.string(splitLine[_POWER_FACTOR])
        ..dq = splitLine[_DQ_PISTOL].toLowerCase() == "yes" || splitLine[_DQ_RIFLE].toLowerCase() == "yes" || splitLine[_DQ_SHOTGUN].toLowerCase() == "yes";

      shootersById[i++] = s;
      match.shooters.add(s);
    } catch(err) {
      debugPrint("Error parsing shooter: $line $err");
    }
  }

  // debugPrint("Read ${shootersById.length} shooters");

  return shootersById;
}

const int _MIN_ROUNDS = 2;
const int _MAX_POINTS = 3;
const int _CLASSIFIER = 4;
const int _CLASSIFIER_NUM = 5;
const int _STAGE_NAME = 6;
const int _SCORING = 7;
Map<int, Stage> _readStageLines(PracticalMatch match, List<String> stageLines) {
  Map<int, Stage> stagesById = {};

  int i = 1;
  int maxPoints = 0;
  for(String line in stageLines) {
    try {
      List<String> splitLine = line.split(",");
      Stage s = Stage(
        minRounds: int.parse(splitLine[_MIN_ROUNDS]),
        maxPoints: int.parse(splitLine[_MAX_POINTS]),
        classifier: splitLine[_CLASSIFIER].toLowerCase() == "yes",
        classifierNumber: splitLine[_CLASSIFIER_NUM],
        name: splitLine[_STAGE_NAME],
        type: ScoringFrom.string(splitLine[_SCORING])
      );

      stagesById[i++] = s;
      maxPoints += s.maxPoints;
      match.stages.add(s);
    } catch(err) {
      debugPrint("Error parsing stage: $line $err");
    }
  }

  match.maxPoints = maxPoints;
  // debugPrint("Read ${stagesById.length} stages");

  return stagesById;
}

const int _STAGE_ID = 1;
const int _SHOOTER_ID = 2;
const int _A = 5;
const int _B = 6;
const int _C = 7;
const int _D = 8;
const int _M = 9;
const int _NS = 10;
const int _PROC = 11;
const int _LATE_SHOT = 14;
const int _EXTRA_SHOT = 15;
const int _EXTRA_HIT = 16;
const int _NPM = 17;
const int _OTHER_PENALTY = 18;
const int _PENALTY_POINTS = 19;
const int _T1 = 20;
const int _T2 = 21;
const int _T3 = 22;
const int _T4 = 23;
const int _T5 = 24;
const int _TIME = 25;
const int _RAW_POINTS = 26;
const int _TOTAL_POINTS = 27;
int _readScoreLines(List<String> stageScoreLines, Map<int, Shooter> shootersByFileId, Map<int, Stage> stagesByFileId) {
  int i = 0;
  for(String line in stageScoreLines) {
    try {
      List<String> splitLine = line.split(",");

      Stage? stage = stagesByFileId[int.parse(splitLine[_STAGE_ID])];
      Shooter? shooter = shootersByFileId[int.parse(splitLine[_SHOOTER_ID])];

      if(stage == null) {
        throw("Null stage for ${int.parse(splitLine[_STAGE_ID])}!");
      }
      if(shooter == null) {
        throw("Null shooter ${int.parse(splitLine[_SHOOTER_ID])}!");
      }

      Score s = Score(shooter: shooter, stage: stage)
        ..a = int.parse(splitLine[_A])
        ..b = int.parse(splitLine[_B])
        ..c = int.parse(splitLine[_C])
        ..d = int.parse(splitLine[_D])
        ..m = int.parse(splitLine[_M])
        ..ns = int.parse(splitLine[_NS])
        ..procedural = int.parse(splitLine[_PROC])
        ..lateShot = int.parse(splitLine[_LATE_SHOT])
        ..extraShot = int.parse(splitLine[_EXTRA_SHOT])
        ..extraHit = int.parse(splitLine[_EXTRA_HIT])
        ..npm = int.parse(splitLine[_NPM])
        ..otherPenalty = int.parse(splitLine[_OTHER_PENALTY])
        //..penaltyPoints = int.parse(splitLine[_PENALTY_POINTS])
        ..t1 = double.parse(splitLine[_T1])
        ..t2 = double.parse(splitLine[_T2])
        ..t3 = double.parse(splitLine[_T3])
        ..t4 = double.parse(splitLine[_T4])
        ..t5 = double.parse(splitLine[_T5])
        ..time = double.parse(splitLine[_TIME]);
        //..rawPoints = int.parse(splitLine[_RAW_POINTS])
        //..totalPoints = int.parse(splitLine[_TOTAL_POINTS]);

      var stageFinished = int.parse(splitLine[_RAW_POINTS]) != 0 && (s.time > 0 || stage.type == Scoring.fixedTime);

      // Work around a PractiScore web results bug: if a shooter has neither points
      // nor time, we can assume it's someone who didn't complete the stage at all.
      if(!stageFinished) {
        shooter.stageScores[stage] = Score(shooter: shooter, stage: stage);
        // debugPrint("Shooter ${shooter.getName()} did not finish ${stage.name}");
        continue;
      }

      shooter.stageScores[stage] = s;

      if(s.penaltyPoints != int.parse(splitLine[_PENALTY_POINTS])) {
        if(verboseParse) debugPrint("Penalty points mismatch for ${shooter.getName()} on ${stage.name}: ${s.penaltyPoints} vs ${splitLine[_PENALTY_POINTS]}");
      }
      if(s.rawPoints != int.parse(splitLine[_RAW_POINTS])) {
        if(verboseParse) debugPrint("Raw points mismatch for ${shooter.getName()} on ${stage.name}: ${s.rawPoints} vs ${splitLine[_RAW_POINTS]}");
      }
      if(s.getTotalPoints(scoreDQ: false) != int.parse(splitLine[_TOTAL_POINTS])) {
        if(verboseParse) debugPrint("Total points mismatch for ${shooter.getName()} on ${stage.name}: ${s.getTotalPoints(scoreDQ: false)} vs ${splitLine[_TOTAL_POINTS]}");
      }

      i++;
    } catch(err) {
      debugPrint("Error parsing score: $line $err");
    }
  }

  // debugPrint("Processed $i stage scores");
  return i;
}