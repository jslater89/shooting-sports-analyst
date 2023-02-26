import 'package:flutter_test/flutter_test.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/ranking/project_manager.dart';
import 'package:uspsa_result_viewer/data/ranking/rater.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/elo/multiplayer_percent_elo_rater.dart';
import 'package:uspsa_result_viewer/data/ranking/rating_error.dart';
import 'package:uspsa_result_viewer/data/ranking/rating_history.dart';

void main() async {

  group("simple deduplication", () {
    test("simple shooter deduplication", () async {
      var matches = deduplicationTestData();

      var history = RatingHistory(matches: matches, progressCallback: (a, b, c) async {});
      await history.processInitialMatches();

      var rater = history.raterFor(history.matches.last, RaterGroup.open);

      expect(rater.uniqueShooters.length, 2);
      var doe = rater.uniqueShooters.firstWhere((element) => element.lastName == "Doe");
      expect(doe.memberNumber, "L1234");
      expect(doe.originalMemberNumber, "L1234");

      // 3 one-stage matches
      expect(doe.length, 3);
    });

    test("copied deduplication", () async {
      var matches = deduplicationTestData();

      var history = RatingHistory(matches: matches, progressCallback: (a, b, c) async {});
      await history.processInitialMatches();

      var rater = history.raterFor(history.matches.last, RaterGroup.open);

      var newRater = Rater.copy(rater);
      expect(newRater.uniqueShooters.length, 2);
    });

    test("post-initial mapping", () async {
      var matches = deduplicationTestData();

      var history = RatingHistory(matches: matches, progressCallback: (a, b, c) async {});
      await history.processInitialMatches();

      await history.addMatch(rdMemberNumberTestData());
      var rater = history.raterFor(history.matches.last, RaterGroup.open);
      expect(rater.uniqueShooters.length, 2);
      var johnson = rater.uniqueShooters.firstWhere((element) => element.lastName == "Johnson");
      expect(johnson.memberNumber, "L5432");
      expect(johnson.originalMemberNumber, "L5432");
    });

  });

  group("blacklist testing", () {
    test("blacklisted mappings", () async {
      var matches = deduplicationTestData();
      RatingHistorySettings settings = RatingHistorySettings(algorithm: MultiplayerPercentEloRater());
      settings.memberNumberMappingBlacklist = {"12345": "L1234"};
      var project = RatingProject(name: "Test", settings: settings, matchUrls: []);
      var history = RatingHistory(project: project, matches: matches);
      await history.processInitialMatches();
      var rater = history.raterFor(history.matches.last, RaterGroup.open);

      expect(rater.uniqueShooters.length, 3);
      var does = rater.uniqueShooters.where((s) => s.lastName == "Doe");
      expect(does.length, 2);
      bool seen1 = false;
      bool seen2 = false;
      for(var d in does) {
        if(d.originalMemberNumber.startsWith("L")) seen1 = true;
        if(d.originalMemberNumber.startsWith("A")) seen2 = true;
      }
      expect(seen1, true);
      expect(seen2, true);
    });

    test("user mappings and blacklist", () async {
      var matches = deduplicationTestData();
      RatingHistorySettings settings = RatingHistorySettings(algorithm: MultiplayerPercentEloRater());
      settings.memberNumberMappingBlacklist = {"12345": "L1234"};
      settings.userMemberNumberMappings = {"12345": "54321"};
      var project = RatingProject(name: "Test", settings: settings, matchUrls: []);
      var history = RatingHistory(project: project, matches: matches);
      var result = await history.processInitialMatches();

      if(result.isErr()) {
        var err = result.unwrapErr() as ShooterMappingError;
        print(err.culprits);
        print(err.accomplices);
      }
      expect(result.isOk(), true);

      var rater = history.raterFor(history.matches.last, RaterGroup.open);

      expect(rater.uniqueShooters.length, 2);
      var does = rater.uniqueShooters.where((s) => s.lastName == "Doe");
      expect(does.length, 1);
      var johnsons = rater.uniqueShooters.where((s) => s.lastName == "Johnson");
      expect(johnsons.length, 1);
      expect(rater.memberNumberMappings["12345"], "54321");
    });
  });
}

List<PracticalMatch> deduplicationTestData() {
  PracticalMatch m1 = PracticalMatch();
  m1.name = "Match 1";
  m1.reportContents = "";
  m1.practiscoreId = "1";
  m1.level = MatchLevel.I;
  m1.date = DateTime(2022, 12, 1, 0, 0, 0);

  Stage s1 = Stage(
    name: "Stage 1",
    internalId: 1,
    classifier: false,
    classifierNumber: "",
    maxPoints: 10,
    minRounds: 2,
    type: Scoring.comstock,
  );

  Shooter shooter1 = Shooter();
  shooter1.firstName = "John";
  shooter1.lastName = "Doe";
  shooter1.memberNumber = "A12345";
  shooter1.powerFactor = PowerFactor.minor;
  shooter1.division = Division.open;
  shooter1.classification = Classification.B;
  shooter1.reentry = false;
  shooter1.dq = false;
  
  shooter1.stageScores = {
    s1: Score(
      shooter: shooter1,
      stage: s1
    )
      ..a=2
      ..time=3.5
  };

  Shooter shooter1b = Shooter();
  shooter1b.firstName = "Bob";
  shooter1b.lastName = "Johnson";
  shooter1b.memberNumber = "A54321";
  shooter1b.powerFactor = PowerFactor.minor;
  shooter1b.division = Division.open;
  shooter1b.classification = Classification.B;
  shooter1b.reentry = false;
  shooter1b.dq = false;

  shooter1b.stageScores = {
    s1: Score(
        shooter: shooter1b,
        stage: s1
    )
      ..a=1
      ..c=1
      ..time=4.5
  };

  m1.shooters = [shooter1, shooter1b];
  m1.stages = [s1];
  m1.maxPoints = s1.maxPoints;
  
  // match 2

  PracticalMatch m2 = PracticalMatch();
  m2.name = "Match 2";
  m2.practiscoreId = "2";
  m2.reportContents = "";
  m2.level = MatchLevel.I;
  m2.date = DateTime(2022, 12, 2, 0, 0, 0);

  Stage s2 = Stage(
    name: "Stage 2",
    internalId: 1,
    classifier: false,
    classifierNumber: "",
    maxPoints: 10,
    minRounds: 2,
    type: Scoring.comstock,
  );

  Shooter shooter2 = Shooter();
  shooter2.firstName = "John";
  shooter2.lastName = "Doe";
  shooter2.memberNumber = "L1234";
  shooter2.powerFactor = PowerFactor.minor;
  shooter2.division = Division.open;
  shooter2.classification = Classification.B;
  shooter2.reentry = false;
  shooter2.dq = false;

  shooter2.stageScores = {
    s2: Score(
        shooter: shooter2,
        stage: s2
    )
      ..a=1
      ..c=1
      ..time=3.5
  };

  Shooter shooter2b = Shooter();
  shooter2b.firstName = "Bob";
  shooter2b.lastName = "Johnson";
  shooter2b.memberNumber = "A54321";
  shooter2b.powerFactor = PowerFactor.minor;
  shooter2b.division = Division.open;
  shooter2b.classification = Classification.B;
  shooter2b.reentry = false;
  shooter2b.dq = false;

  shooter2b.stageScores = {
    s2: Score(
        shooter: shooter2b,
        stage: s2
    )
      ..c=2
      ..time=3.25
  };

  m2.shooters = [shooter2, shooter2b];
  m2.stages = [s2];
  m2.maxPoints = s2.maxPoints;
  
  // match 3

  PracticalMatch m3 = PracticalMatch();
  m3.name = "Match 3";
  m3.practiscoreId = "2";
  m3.reportContents = "";
  m3.level = MatchLevel.I;
  m3.date = DateTime(2022, 12, 2, 0, 0, 0);

  Stage s3 = Stage(
    name: "Stage 3",
    internalId: 1,
    classifier: false,
    classifierNumber: "",
    maxPoints: 10,
    minRounds: 2,
    type: Scoring.comstock,
  );

  Shooter shooter3 = Shooter();
  shooter3.firstName = "John";
  shooter3.lastName = "Doe";
  shooter3.memberNumber = "A12345";
  shooter3.powerFactor = PowerFactor.minor;
  shooter3.division = Division.open;
  shooter3.classification = Classification.B;
  shooter3.reentry = false;
  shooter3.dq = false;

  shooter3.stageScores = {
    s3: Score(
        shooter: shooter3,
        stage: s3
    )
      ..a=1
      ..c=1
      ..time=3.5
  };

  Shooter shooter3b = Shooter();
  shooter3b.firstName = "Bob";
  shooter3b.lastName = "Johnson";
  shooter3b.memberNumber = "A54321";
  shooter3b.powerFactor = PowerFactor.minor;
  shooter3b.division = Division.open;
  shooter3b.classification = Classification.B;
  shooter3b.reentry = false;
  shooter3b.dq = false;

  shooter3b.stageScores = {
    s3: Score(
        shooter: shooter3b,
        stage: s3
    )
      ..c=2
      ..time=3.25
  };

  m3.shooters = [shooter3, shooter3b];
  m3.stages = [s3];
  m3.maxPoints = s3.maxPoints;

  return [m1, m2, m3];
}

PracticalMatch rdMemberNumberTestData() {
  PracticalMatch m3 = PracticalMatch();
  m3.name = "Match 4";
  m3.practiscoreId = "2";
  m3.reportContents = "";
  m3.level = MatchLevel.I;
  m3.date = DateTime(2022, 12, 2, 0, 0, 0);

  Stage s3 = Stage(
    name: "Stage 2",
    internalId: 1,
    classifier: false,
    classifierNumber: "",
    maxPoints: 10,
    minRounds: 2,
    type: Scoring.comstock,
  );

  Shooter shooter3 = Shooter();
  shooter3.firstName = "John";
  shooter3.lastName = "Doe";
  shooter3.memberNumber = "L1234";
  shooter3.powerFactor = PowerFactor.minor;
  shooter3.division = Division.open;
  shooter3.classification = Classification.B;
  shooter3.reentry = false;
  shooter3.dq = false;

  shooter3.stageScores = {
    s3: Score(
        shooter: shooter3,
        stage: s3
    )
      ..a=1
      ..c=1
      ..time=3.5
  };

  Shooter shooter3b = Shooter();
  shooter3b.firstName = "Bob";
  shooter3b.lastName = "Johnson";
  shooter3b.memberNumber = "L5432";
  shooter3b.powerFactor = PowerFactor.minor;
  shooter3b.division = Division.open;
  shooter3b.classification = Classification.B;
  shooter3b.reentry = false;
  shooter3b.dq = false;

  shooter3b.stageScores = {
    s3: Score(
        shooter: shooter3b,
        stage: s3
    )
      ..c=2
      ..time=3.25
  };

  m3.shooters = [shooter3, shooter3b];
  m3.stages = [s3];
  m3.maxPoints = s3.maxPoints;
  
  return m3;
}