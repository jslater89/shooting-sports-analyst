import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/ranking/rating_history.dart';

void main() async {
  var matches = deduplicationTestData();

  var history = RatingHistory(matches: matches, progressCallback: (a, b, c) async {});
  await history.processInitialMatches();

  var rater = history.raterFor(history.matches.last, RaterGroup.open);

  assert(rater.uniqueShooters.length == 2);
}

List<PracticalMatch> deduplicationTestData() {
  PracticalMatch m1 = PracticalMatch();
  m1.name = "Match 1";
  m1.practiscoreId = "1";
  m1.level = MatchLevel.I;
  m1.date = DateTime(2022, 12, 1, 0, 0, 0);

  Stage s1 = Stage(
    name: "Stage 1",
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

  PracticalMatch m2 = PracticalMatch();
  m2.name = "Match 2";
  m2.practiscoreId = "2";
  m2.level = MatchLevel.I;
  m2.date = DateTime(2022, 12, 2, 0, 0, 0);

  Stage s2 = Stage(
    name: "Stage 2",
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

  return [m1, m2];
}