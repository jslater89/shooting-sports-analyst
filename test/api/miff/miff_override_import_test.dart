/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "dart:convert";
import "dart:io";

import "package:flutter_test/flutter_test.dart";
import "package:shooting_sports_analyst/api/miff/impl/miff_exporter.dart";
import "package:shooting_sports_analyst/api/miff/impl/miff_importer.dart";
import "package:shooting_sports_analyst/api/miff/impl/miff_validator.dart";
import "package:shooting_sports_analyst/data/sport/builtins/registry.dart";
import "package:shooting_sports_analyst/data/sport/match/match.dart";
import "package:shooting_sports_analyst/data/sport/scoring/scoring.dart";
import "package:shooting_sports_analyst/data/sport/shooter/shooter.dart";
import "package:shooting_sports_analyst/data/sport/sport.dart";

Map<String, dynamic> _overrideMatchJson({
  required Map<String, dynamic> score,
}) {
  return {
    "format": "miff",
    "version": "1.3",
    "match": {
      "name": "Override Import Test",
      "date": "2024-06-01",
      "sport": "uspsa",
      "stages": [
        {
          "id": 1,
          "name": "Stage 1",
          "scoring": {"type": "hitFactor"},
        },
      ],
      "shooters": [
        {
          "id": 1,
          "firstName": "Jane",
          "lastName": "Shooter",
          "memberNumber": "A99999",
          "powerFactor": "Major",
          "scores": {
            "1": score,
          },
        },
      ],
    },
  };
}

List<int> _gzipJson(Map<String, dynamic> json) {
  return gzip.encode(utf8.encode(jsonEncode(json)));
}

ShootingMatch _matchWithScore(RawScore score) {
  var sport = SportRegistry().availableSports.firstWhere((s) => s.type == SportType.uspsa);
  var stage = MatchStage(
    stageId: 1,
    name: "Stage 1",
    scoring: const HitFactorScoring(),
  );
  var shooter = MatchEntry(
    entryId: 1,
    firstName: "Jane",
    lastName: "Shooter",
    memberNumber: "A99999",
    powerFactor: sport.powerFactors.lookupByName("Major")!,
    scores: {
      stage: score,
    },
  );
  return ShootingMatch(
    name: "Override Export Test",
    rawDate: "",
    date: DateTime(2024, 6, 1),
    stages: [stage],
    sport: sport,
    shooters: [shooter],
  );
}

Map<String, dynamic> _exportedScoreJson(ShootingMatch match) {
  var json = MiffExporter().toJson(match);
  var shooters = (json["match"]["shooters"] as List).cast<Map<String, dynamic>>();
  var scores = shooters.first["scores"] as Map<String, dynamic>;
  return scores["1"] as Map<String, dynamic>;
}

void main() {
  late MiffImporter importer;
  late MiffValidator validator;

  setUp(() {
    importer = MiffImporter();
    validator = MiffValidator();
  });

  test("Imports totalPointsOverride and finalTimeOverride", () {
    var json = _overrideMatchJson(score: {
      "time": 10.0,
      "totalPointsOverride": 120,
      "finalTimeOverride": 11.5,
    });
    var bytes = _gzipJson(json);

    expect(validator.validate(bytes).isOk(), isTrue);

    var result = importer.importMatch(bytes);
    expect(result.isOk(), isTrue, reason: result.isErr() ? result.unwrapErr().message : null);

    var score = result.unwrap().shooters.first.scores.values.first;
    expect(score.rawTime, 10.0);
    expect(score.pointsOverride, 120);
    expect(score.finalTimeOverride, 11.5);
    expect(score.points, 120);
    expect(score.finalTime, 11.5);
    expect(score.targetEvents, isEmpty);
    expect(score.penaltyEvents, isEmpty);
    expect(score.hitFactor, closeTo(12.0, 0.0001));
  });

  test("Imports totalPointsOverride alone and uses time as final time", () {
    var json = _overrideMatchJson(score: {
      "time": 10.0,
      "totalPointsOverride": 95,
    });
    var bytes = _gzipJson(json);

    expect(validator.validate(bytes).isOk(), isTrue);

    var result = importer.importMatch(bytes);
    expect(result.isOk(), isTrue, reason: result.isErr() ? result.unwrapErr().message : null);

    var score = result.unwrap().shooters.first.scores.values.first;
    expect(score.pointsOverride, 95);
    expect(score.finalTimeOverride, isNull);
    expect(score.points, 95);
    expect(score.finalTime, 10.0);
    expect(score.hitFactor, closeTo(9.5, 0.0001));
  });

  test("Imports finalTimeOverride alone", () {
    var json = _overrideMatchJson(score: {
      "time": 10.0,
      "finalTimeOverride": 11.5,
    });
    var bytes = _gzipJson(json);

    expect(validator.validate(bytes).isOk(), isTrue);

    var result = importer.importMatch(bytes);
    expect(result.isOk(), isTrue, reason: result.isErr() ? result.unwrapErr().message : null);

    var score = result.unwrap().shooters.first.scores.values.first;
    expect(score.finalTimeOverride, 11.5);
    expect(score.pointsOverride, isNull);
    expect(score.finalTime, 11.5);
    expect(score.points, 0);
    expect(score.targetEvents, isEmpty);
  });

  test("Event-count scores still import without overrides", () {
    var json = _overrideMatchJson(score: {
      "time": 10.0,
      "targetEvents": {"A": 8, "C": 2},
      "penaltyEvents": {"Procedural": 1},
    });
    var bytes = _gzipJson(json);

    expect(validator.validate(bytes).isOk(), isTrue);

    var result = importer.importMatch(bytes);
    expect(result.isOk(), isTrue, reason: result.isErr() ? result.unwrapErr().message : null);

    var score = result.unwrap().shooters.first.scores.values.first;
    expect(score.pointsOverride, isNull);
    expect(score.finalTimeOverride, isNull);
    // 8A*5 + 2C*4 + 1P*-10 = 40 + 8 - 10 = 38
    expect(score.points, 38);
    expect(score.finalTime, 10.0);
  });

  test("Exports override scores in override mode", () {
    var match = _matchWithScore(RawScore(
      scoring: const HitFactorScoring(),
      rawTime: 10.0,
      targetEvents: {},
      pointsOverride: 120,
      finalTimeOverride: 11.5,
    ));
    var scoreJson = _exportedScoreJson(match);
    var fullJson = MiffExporter().toJson(match);

    expect(validator.validateJson(fullJson).isOk(), isTrue);
    expect(scoreJson["time"], 10.0);
    expect(scoreJson["totalPointsOverride"], 120);
    expect(scoreJson["finalTimeOverride"], 11.5);
    expect(scoreJson.containsKey("targetEvents"), isFalse);
    expect(scoreJson.containsKey("penaltyEvents"), isFalse);
  });

  test("Exports points override alone without event maps", () {
    var match = _matchWithScore(RawScore(
      scoring: const HitFactorScoring(),
      rawTime: 10.0,
      targetEvents: {},
      pointsOverride: 95,
    ));
    var scoreJson = _exportedScoreJson(match);

    expect(validator.validateJson(MiffExporter().toJson(match)).isOk(), isTrue);
    expect(scoreJson["totalPointsOverride"], 95);
    expect(scoreJson.containsKey("finalTimeOverride"), isFalse);
    expect(scoreJson.containsKey("targetEvents"), isFalse);
    expect(scoreJson.containsKey("penaltyEvents"), isFalse);
  });

  test("Exports final time override alone without event maps", () {
    var match = _matchWithScore(RawScore(
      scoring: const HitFactorScoring(),
      rawTime: 10.0,
      targetEvents: {},
      finalTimeOverride: 11.5,
    ));
    var scoreJson = _exportedScoreJson(match);

    expect(validator.validateJson(MiffExporter().toJson(match)).isOk(), isTrue);
    expect(scoreJson["finalTimeOverride"], 11.5);
    expect(scoreJson.containsKey("totalPointsOverride"), isFalse);
    expect(scoreJson.containsKey("targetEvents"), isFalse);
  });

  test("Override export omits event maps even when the score has hits", () {
    var sport = SportRegistry().availableSports.firstWhere((s) => s.type == SportType.uspsa);
    var major = sport.powerFactors.lookupByName("Major")!;
    var match = _matchWithScore(RawScore(
      scoring: const HitFactorScoring(),
      rawTime: 10.0,
      targetEvents: {
        major.targetEvents.lookupByName("A")!: 8,
      },
      penaltyEvents: {
        major.penaltyEvents.lookupByName("Procedural")!: 1,
      },
      pointsOverride: 120,
    ));
    var scoreJson = _exportedScoreJson(match);

    expect(validator.validateJson(MiffExporter().toJson(match)).isOk(), isTrue);
    expect(scoreJson["totalPointsOverride"], 120);
    expect(scoreJson.containsKey("targetEvents"), isFalse);
    expect(scoreJson.containsKey("penaltyEvents"), isFalse);
  });

  test("Event-count scores still export as aggregated events", () {
    var sport = SportRegistry().availableSports.firstWhere((s) => s.type == SportType.uspsa);
    var major = sport.powerFactors.lookupByName("Major")!;
    var match = _matchWithScore(RawScore(
      scoring: const HitFactorScoring(),
      rawTime: 10.0,
      targetEvents: {
        major.targetEvents.lookupByName("A")!: 8,
        major.targetEvents.lookupByName("C")!: 2,
      },
    ));
    var scoreJson = _exportedScoreJson(match);

    expect(validator.validateJson(MiffExporter().toJson(match)).isOk(), isTrue);
    expect(scoreJson["targetEvents"], {"A": 8, "C": 2});
    expect(scoreJson.containsKey("totalPointsOverride"), isFalse);
    expect(scoreJson.containsKey("finalTimeOverride"), isFalse);
  });

  test("Override scores round-trip through export and import", () {
    var original = _matchWithScore(RawScore(
      scoring: const HitFactorScoring(),
      rawTime: 10.0,
      targetEvents: {},
      pointsOverride: 120,
      finalTimeOverride: 11.5,
    ));
    var exported = MiffExporter().exportMatch(original);
    expect(exported.isOk(), isTrue);
    expect(validator.validate(exported.unwrap()).isOk(), isTrue);

    var imported = importer.importMatch(exported.unwrap());
    expect(imported.isOk(), isTrue, reason: imported.isErr() ? imported.unwrapErr().message : null);

    var score = imported.unwrap().shooters.first.scores.values.first;
    expect(score.rawTime, 10.0);
    expect(score.pointsOverride, 120);
    expect(score.finalTimeOverride, 11.5);
    expect(score.points, 120);
    expect(score.finalTime, 11.5);
    expect(score.targetEvents, isEmpty);
  });
}
