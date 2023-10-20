import 'package:intl/intl.dart';
import 'package:uspsa_result_viewer/data/results_file_parser.dart';
import 'package:uspsa_result_viewer/data/sport/match/match.dart';
import 'package:uspsa_result_viewer/data/sport/scoring/scoring.dart';
import 'package:uspsa_result_viewer/data/sport/shooter/shooter.dart';
import 'package:uspsa_result_viewer/data/sport/sport.dart';
import 'package:uspsa_result_viewer/util.dart';

/// This will parse a PractiScore hit factor report.txt file.
///
/// The sport definition must broadly match USPSA: each power factor
/// must have a scoring event for A, C, D, M, and NS. B and NPM are
/// optional. Each must also have a penalty named 'Procedural' and a
/// penalty named 'Overtime shot'.
///
/// If the sport has event levels, they must match the PractiScore I/II/III
/// format in one of the name fields.
class PractiscoreHitFactorReportParser {
  Sport sport;
  bool verboseParse;

  PractiscoreHitFactorReportParser(this.sport, {this.verboseParse = false});

  Result<ShootingMatch, Error> parseWebReport(String fileContents) {
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

    try {
      Map<int, MatchStage> stagesByFileId = _readStageLines(stageLines);
      Map<int, MatchEntry> shootersByFileId = _readCompetitorLines(competitorLines);
      _readScoreLines(stageScoreLines, stagesByFileId, shootersByFileId);
      var info = _readInfoLines(infoLines);

      ShootingMatch m = ShootingMatch(
        eventName: info.name,
        date: info.date,
        rawDate: info.rawDate,
        level: info.level,
        sport: sport,
        stages: stagesByFileId.values.toList(),
        shooters: shootersByFileId.values.toList(),
      );
      return Result.ok(m);
    } catch(e) {
      return Result.err(MatchGetError.formatError);
    }
  }

  static const String _MATCH_NAME = r"$INFO Match name:";
  static const String _MATCH_DATE = r"$INFO Match date:";
  static const String _MATCH_LEVEL = r"$INFO Match Level:";
  static final DateFormat _df = DateFormat("MM/dd/yyyy");
  _MatchInfo _readInfoLines(List<String> infoLines) {
    var info = _MatchInfo();
    for(String line in infoLines) {
      if(line.startsWith(_MATCH_NAME)) {
        // print("Found match name");
        info.name = line.replaceFirst(_MATCH_NAME, "");
      }
      else if(line.startsWith(_MATCH_DATE)) {
        // print("Found match date");
        info.rawDate = line.replaceFirst(_MATCH_DATE, "");
        try {
          info.date = _df.parse(info.rawDate);
        }
        catch(e) {
          print("Unable to parse date ${info.rawDate} $e");
        }
      }
      else if(line.startsWith(_MATCH_LEVEL) && sport.hasEventLevels) {
        var level = line.replaceFirst(_MATCH_LEVEL, "");
        info.level = sport.eventLevels.lookupByName(level);

        // print("${match.name} has $level => ${match.level}");
      }
    }

    return info;
  }

  static const int _MIN_ROUNDS = 2;
  static const int _MAX_POINTS = 3;
  static const int _CLASSIFIER = 4;
  static const int _CLASSIFIER_NUM = 5;
  static const int _STAGE_NAME = 6;
  static const int _SCORING = 7;
  Map<int, MatchStage> _readStageLines(List<String> stageLines) {
    Map<int, MatchStage> stagesById = {};

    int i = 1;
    for(String line in stageLines) {
      try {
        List<String> splitLine = line.split(",");
        MatchStage s = MatchStage(
          stageId: i,
          minRounds: int.parse(splitLine[_MIN_ROUNDS]),
          maxPoints: int.parse(splitLine[_MAX_POINTS]),
          classifier: splitLine[_CLASSIFIER].toLowerCase() == "yes",
          classifierNumber: splitLine[_CLASSIFIER_NUM],
          name: splitLine[_STAGE_NAME],
          // default scoring to Comstock for matches (looking at you, Doc Welt)
          // that somehow manage to generate an invalid scores file
          scoring : splitLine.length > _SCORING ? _translateScoring(splitLine[_SCORING]) : sport.defaultStageScoring,
        );

        stagesById[i++] = s;
      } catch(err) {
        print("Error parsing stage: $line $err");
      }
    }

    return stagesById;
  }

  StageScoring _translateScoring(String value) {
    value = value.toLowerCase();
    if(value == "fixed") return const PointsScoring();
    if(value == "comstock" || value == "virginia") return const HitFactorScoring();
    if(value == "chrono") return const IgnoredScoring();
    return sport.defaultStageScoring;
  }

  static const int _MEMBER_NUM = 1;
  static const int _FIRST_NAME = 2;
  static const int _LAST_NAME = 3;
  static const int _DQ_PISTOL = 4;
  static const int _DQ_RIFLE = 5;
  static const int _DQ_SHOTGUN = 6;
  static const int _REENTRY = 7;
  static const int _CLASS = 8;
  static const int _DIVISION = 9;
  static const int _POWER_FACTOR = 12;
  static const int _LADY = 33;
  static const int _AGE = 34;
  static const int _LAW_ENFORCEMENT = 35;
  static const int _MILITARY = 36;
  Map<int, MatchEntry> _readCompetitorLines(List<String> competitorLines) {
    Map<int, MatchEntry> shootersById = {};

    int i = 1;
    for(String line in competitorLines) {
      try {
        List<String> splitLine = line.split(",");

        late PowerFactor pf;
        if(sport.hasPowerFactors) {
          var found = sport.powerFactors.values.lookupByName(splitLine[_POWER_FACTOR]);
          if(found == null) {
            throw ArgumentError("Shooter has non-matching power factor ${splitLine[_POWER_FACTOR]}");
          }
          pf = found;
        }
        else {
          pf = sport.powerFactors.values.first;
        }

        Classification? cls;
        Division? division;
        if(sport.hasClassifications) {
          cls = sport.classifications.values.lookupByName(splitLine[_CLASS]);
        }
        if(sport.hasDivisions) {
          division = sport.divisions.values.lookupByName(splitLine[_DIVISION]);
        }

        MatchEntry s = MatchEntry(
          entryId: i,
          firstName: splitLine[_FIRST_NAME],
          lastName: splitLine[_LAST_NAME],
          memberNumber: splitLine[_MEMBER_NUM],
          powerFactor: pf,
          scores: {},
          division: division,
          classification: cls,
          reentry: splitLine[_REENTRY].toLowerCase() == "yes",
          female: splitLine[_LADY].toLowerCase() == "yes",
          dq: splitLine[_DQ_PISTOL].toLowerCase() == "yes" || splitLine[_DQ_RIFLE].toLowerCase() == "yes" || splitLine[_DQ_SHOTGUN].toLowerCase() == "yes",
        );

        shootersById[i++] = s;
      } catch(err) {
        print("Error parsing shooter: $line $err");
      }
    }

    // print("Read ${shootersById.length} shooters");

    return shootersById;
  }

  static const int _STAGE_ID = 1;
  static const int _SHOOTER_ID = 2;
  static const int _A = 5;
  static const int _B = 6;
  static const int _C = 7;
  static const int _D = 8;
  static const int _M = 9;
  static const int _NS = 10;
  static const int _PROC = 11;
  static const int _LATE_SHOT = 14;
  static const int _EXTRA_SHOT = 15;
  static const int _EXTRA_HIT = 16;
  static const int _NPM = 17;
  static const int _OTHER_PENALTY = 18;
  static const int _PENALTY_POINTS = 19;
  static const int _T1 = 20;
  static const int _T2 = 21;
  static const int _T3 = 22;
  static const int _T4 = 23;
  static const int _T5 = 24;
  static const int _TIME = 25;
  static const int _RAW_POINTS = 26;
  static const int _TOTAL_POINTS = 27;
  int _readScoreLines(List<String> stageScoreLines, Map<int, MatchStage> stagesByFileId, Map<int, MatchEntry> shootersByFileId) {
    int i = 0;
    Map<int, Map<MatchStage, RawScore>> scores = {};

    for (String line in stageScoreLines) {
      try {
        List<String> splitLine = line.split(",");

        MatchStage? stage = stagesByFileId[int.parse(splitLine[_STAGE_ID])];
        MatchEntry? shooter = shootersByFileId[int.parse(splitLine[_SHOOTER_ID])];

        if (stage == null) {
          throw("Null stage for ${int.parse(splitLine[_STAGE_ID])}!");
        }
        if (shooter == null) {
          throw("Null shooter for ${int.parse(splitLine[_SHOOTER_ID])}!");
        }

        // For times greater than 1000 seconds, Practiscore displays them
        // as "1,000.00" and stores them as "1.000.00"
        bool correctedTime = false;

        var timeField = splitLine[_TIME];
        var originalTimeField = timeField;
        while (timeField
            .split(".")
            .length > 2) {
          timeField = timeField.replaceFirst(".", "");
          correctedTime = true;
        }

        if (verboseParse && correctedTime) print("Corrected time $originalTimeField to $timeField");

        var powerFactor = shooter.powerFactor;
        Map<ScoringEvent, int> scoringEvents = {};
        Map<ScoringEvent, int> penaltyEvents = {};

        int aCount = int.parse(splitLine[_A]);
        int bCount = int.parse(splitLine[_B]);
        int cCount = int.parse(splitLine[_C]);
        int dCount = int.parse(splitLine[_D]);
        int mCount = int.parse(splitLine[_M]);
        int nsCount = int.parse(splitLine[_NS]);
        int npmCount = int.parse(splitLine[_NPM]);

        scoringEvents[powerFactor.targetEvents.lookupByName("A")!] = aCount;
        var bZone = powerFactor.targetEvents.lookupByName("B");
        if(bZone != null) {
          scoringEvents[bZone] = bCount;
        }
        scoringEvents[powerFactor.targetEvents.lookupByName("C")!] = cCount;
        scoringEvents[powerFactor.targetEvents.lookupByName("D")!] = dCount;
        scoringEvents[powerFactor.targetEvents.lookupByName("M")!] = mCount;
        scoringEvents[powerFactor.targetEvents.lookupByName("NS")!] = nsCount;
        scoringEvents[powerFactor.targetEvents.lookupByName("NPM")!] = npmCount;

        int penaltyCount = int.parse(splitLine[_PROC])
            + int.parse(splitLine[_EXTRA_SHOT])
            + int.parse(splitLine[_EXTRA_HIT])
            + int.parse(splitLine[_OTHER_PENALTY]);
        int overtimeShotCount = int.parse(splitLine[_LATE_SHOT]);

        penaltyEvents[powerFactor.penaltyEvents.lookupByName("Procedural")!] = penaltyCount;
        penaltyEvents[powerFactor.penaltyEvents.lookupByName("Overtime shot")!] = overtimeShotCount;

        List<double> stringTimes = [
          double.parse(splitLine[_T1]),
          double.parse(splitLine[_T2]),
          double.parse(splitLine[_T3]),
          double.parse(splitLine[_T4]),
          double.parse(splitLine[_T5]),
        ];

        RawScore s = RawScore(
          scoring: stage.scoring,
          rawTime: double.parse(timeField),
          stringTimes: stringTimes..retainWhere((element) => element > 0),
          scoringEvents: scoringEvents,
          penaltyEvents: penaltyEvents,
        );

        // Work around a PractiScore web results bug: if a shooter has neither points
        // nor time, we can assume it's someone who didn't complete the stage at all.
        if (s.dnf) {
          shooter.scores[stage] = s;
          // print("Shooter ${shooter.getName()} did not finish ${stage.name}");
          continue;
        }

        shooter.scores[stage] = s;

        i++;
      } catch (err) {
        print("Error parsing score: $line $err");
      }
    }
    if(verboseParse) print("Processed $i stage scores");
    return i;
  }
}

class _MatchInfo {
  String name = "";
  String rawDate = "";
  DateTime date = DateTime.now();
  MatchLevel? level;
}