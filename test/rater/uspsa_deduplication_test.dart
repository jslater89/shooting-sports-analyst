/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/match/rating_project_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/action.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/conflict.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/shooter_deduplicator.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/uspsa_deduplicator.dart';
import 'package:shooting_sports_analyst/data/ranking/legacy_loader/project_manager.dart';
import 'package:shooting_sports_analyst/data/ranking/member_number_correction.dart';
import 'package:shooting_sports_analyst/data/ranking/project_settings.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/elo/multiplayer_percent_elo_rater.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/uspsa.dart';
import 'package:shooting_sports_analyst/data/sport/model.dart';
import 'package:shooting_sports_analyst/util.dart';
import 'package:uuid/uuid.dart';

void main() async {
  var db = AnalystDatabase.test();
  var ratingGroup = uspsaSport.builtinRatingGroupsProvider!.divisionRatingGroups.firstWhere((e) => e.name == "Open");

  setUpAll(() async {
    print("Setting up test data");
    await setupTestDb(db);
  });

  // #region Tests

  test("DataEntryFix Similar Numbers", () async {
    var project = DbRatingProject(
      name: "DataEntryFix Test Project",
      sportName: uspsaSport.name,
      settings: RatingProjectSettings(
        algorithm: MultiplayerPercentEloRater(),
      )
    );

    var newRatings = await addMatchToTest(db, project, "data-entry-fix-similar-numbers");
    var deduplicator = USPSADeduplicator();
    var deduplication = await deduplicator.deduplicateShooters(
      ratingProject: project,
      newRatings: newRatings,
      checkDataEntryErrors: true,
      group: ratingGroup,
    );

    expect(deduplication.isOk(), isTrue);

    var results = deduplication.unwrap();
    expect(reason: "number of results", results, hasLength(1));
    expect(reason: "number of causes", results[0].causes, hasLength(1));
    expect(reason: "number of proposed actions", results[0].proposedActions, hasLength(1));
    expect(reason: "proposed action is DataEntryFix", results[0].proposedActions.first, isA<DataEntryFix>());
    var fix = results[0].proposedActions.first as DataEntryFix;
    expect(reason: "target number", fix.targetNumber, equals("A123456"));
    expect(reason: "source number", fix.sourceNumber, equals("A123457"));
  });

  test("DataEntryFix Dissimilar Numbers", () async {
    var project = DbRatingProject(
      name: "DataEntryFix Test Project 2",
      sportName: uspsaSport.name,
      settings: RatingProjectSettings(
        algorithm: MultiplayerPercentEloRater(),
      )
    );

    var newRatings = await addMatchToTest(db, project, "data-entry-fix-dissimilar-numbers");
    var deduplicator = USPSADeduplicator();
    var deduplication = await deduplicator.deduplicateShooters(
      ratingProject: project,
      newRatings: newRatings,
      checkDataEntryErrors: true,
      group: ratingGroup,
    );

    expect(deduplication.isOk(), isTrue);

    var results = deduplication.unwrap();
    expect(reason: "number of results", results, hasLength(1));
    expect(reason: "number of causes", results[0].causes, hasLength(1));
    expect(reason: "number of proposed actions", results[0].proposedActions, hasLength(1));
    expect(reason: "proposed action is DataEntryFix", results[0].proposedActions.first, isA<Blacklist>());
    var fix = results[0].proposedActions.first as Blacklist;
    expect(reason: "target number", fix.targetNumber, equals("A123456"));
    expect(reason: "source number", fix.sourceNumber, equals("A76691"));
  });

  test("User-Mapped Dissimilar Numbers", () async {
    var project = DbRatingProject(
      name: "DataEntryFix User-Mapped",
      sportName: uspsaSport.name,
      settings: RatingProjectSettings(
        algorithm: MultiplayerPercentEloRater(),
        userMemberNumberMappings: {
          "A76691": "A123456",
        },
        memberNumberMappingBlacklist: {},
      )
    );

    var newRatings = await addMatchToTest(db, project, "data-entry-fix-user-mapped");
    var deduplicator = USPSADeduplicator();
    var deduplication = await deduplicator.deduplicateShooters(
      ratingProject: project,
      newRatings: newRatings,
      checkDataEntryErrors: true,
      group: ratingGroup,
    );

    expect(deduplication.isOk(), isTrue);
    var results = deduplication.unwrap();
    expect(reason: "number of results", results, hasLength(1));
    expect(reason: "number of causes", results[0].causes, hasLength(1));
    expect(reason: "cause is FixedInSettings", results[0].causes.first, isA<FixedInSettings>());
    expect(reason: "number of proposed actions", results[0].proposedActions, hasLength(1));
    expect(reason: "proposed action is PreexistingMapping", results[0].proposedActions.first, isA<PreexistingMapping>());
    var fix = results[0].proposedActions.first as PreexistingMapping;
    expect(reason: "target number", fix.targetNumber, equals("A123456"));
    expect(reason: "source number", fix.sourceNumber, equals("A76691"));
  });

  test("User-Mapped Dissimilar Numbers", () async {
    var project = DbRatingProject(
      name: "DataEntryFix User-Mapped",
      sportName: uspsaSport.name,
      settings: RatingProjectSettings(
        algorithm: MultiplayerPercentEloRater(),
        userMemberNumberMappings: {
          "A76691": "A123456",
        },
        memberNumberMappingBlacklist: {},
      )
    );

    var newRatings = await addMatchToTest(db, project, "data-entry-fix-user-mapped");
    var deduplicator = USPSADeduplicator();
    var deduplication = await deduplicator.deduplicateShooters(
      ratingProject: project,
      newRatings: newRatings,
      checkDataEntryErrors: true,
      group: ratingGroup,
    );

    expect(deduplication.isOk(), isTrue);
    var results = deduplication.unwrap();
    expect(reason: "number of results", results, hasLength(1));
    expect(reason: "number of causes", results[0].causes, hasLength(1));
    expect(reason: "cause is FixedInSettings", results[0].causes.first, isA<FixedInSettings>());
    expect(reason: "number of proposed actions", results[0].proposedActions, hasLength(1));
    expect(reason: "proposed action is PreexistingMapping", results[0].proposedActions.first, isA<PreexistingMapping>());
    var fix = results[0].proposedActions.first as PreexistingMapping;
    expect(reason: "target number", fix.targetNumber, equals("A123456"));
    expect(reason: "source number", fix.sourceNumber, equals("A76691"));
  });

  test("Resolvable Cross Mapping", () async {
    var project = DbRatingProject(
      name: "Resolvable Cross Mapping",
      sportName: uspsaSport.name,
      automaticNumberMappings: [
        DbMemberNumberMapping(
          deduplicatorName: "johndeduplicator",
          sourceNumbers: ["A123456"],
          targetNumber: "L1234",
          automatic: true,
        ),
      ],
      settings: RatingProjectSettings(
        algorithm: MultiplayerPercentEloRater(),
        userMemberNumberMappings: {
          "L1234": "B123",
        },
        memberNumberMappingBlacklist: {},
      )
    );

    var newRatings = await addMatchToTest(db, project, "resolvable-cross-mapping");
    var deduplicator = USPSADeduplicator();
    var deduplication = await deduplicator.deduplicateShooters(
      ratingProject: project,
      newRatings: newRatings,
      checkDataEntryErrors: true,
      group: ratingGroup,
    );

    expect(deduplication.isOk(), isTrue);
    var results = deduplication.unwrap();
    expect(reason: "number of results", results, hasLength(1));
    expect(reason: "number of causes", results[0].causes, hasLength(2));
    var fixedInSettings = results[0].causes.firstWhereOrNull((e) => e is FixedInSettings) as FixedInSettings;
    var ambiguousMapping = results[0].causes.firstWhereOrNull((e) => e is AmbiguousMapping) as AmbiguousMapping;
    expect(reason: "causes contains FixedInSettings", fixedInSettings, isNotNull);
    expect(reason: "causes contains AmbiguousMapping", ambiguousMapping, isNotNull);
    expect(reason: "number of proposed actions", results[0].proposedActions, hasLength(2));
    var actions = results[0].proposedActions.cast<PreexistingMapping>();
    expect(reason: "proposed actions contains A->B mapping", actions, predicate<List<PreexistingMapping>>((list) => list.any((e) => e.sourceNumber == "A123456" && e.targetNumber == "B123")));
    expect(reason: "proposed actions contains L->B mapping", actions, predicate<List<PreexistingMapping>>((list) => list.any((e) => e.sourceNumber == "L1234" && e.targetNumber == "B123")));
  });

  test("Resolvable Cross Mapping 2", () async {
    var project = DbRatingProject(
      name: "Resolvable Cross Mapping 2",
      sportName: uspsaSport.name,
      automaticNumberMappings: [
        DbMemberNumberMapping(
          deduplicatorName: "johndeduplicator",
          sourceNumbers: ["A123456"],
          targetNumber: "L1234",
          automatic: true,
        ),
      ],
      settings: RatingProjectSettings(
        algorithm: MultiplayerPercentEloRater(),
        userMemberNumberMappings: {
          "A123456": "L1235",
        },
        memberNumberMappingBlacklist: {},
      )
    );

    var newRatings = await addMatchToTest(db, project, "resolvable-cross-mapping-2");
    var deduplicator = USPSADeduplicator();
    var deduplication = await deduplicator.deduplicateShooters(
      ratingProject: project,
      newRatings: newRatings,
      checkDataEntryErrors: true,
      group: ratingGroup,
    );

    expect(deduplication.isOk(), isTrue);
    var results = deduplication.unwrap();
    expect(reason: "number of results", results, hasLength(1));
    expect(reason: "number of causes", results[0].causes, hasLength(1));
    expect(reason: "cause is MultipleNumbersOfType", results[0].causes.first, isA<MultipleNumbersOfType>());
    expect(reason: "number of proposed actions", results[0].proposedActions, hasLength(2));
    var preexistingMapping = results[0].proposedActions.firstWhereOrNull((e) => e is PreexistingMapping) as PreexistingMapping;
    expect(reason: "preexisting mapping source number", preexistingMapping.sourceNumber, equals("A123456"));
    expect(reason: "preexisting mapping target number", preexistingMapping.targetNumber, equals("L1235"));
    var dataEntryFix = results[0].proposedActions.firstWhereOrNull((e) => e is DataEntryFix) as DataEntryFix;
    expect(reason: "data entry fix source number", dataEntryFix.sourceNumber, equals("L1235"));
    expect(reason: "data entry fix target number", dataEntryFix.targetNumber, equals("L1234"));
  });

  test("Auto-Mapped Dissimilar Numbers", () async {
    var project = DbRatingProject(
      name: "DataEntryFix Auto-Mapped",
      sportName: uspsaSport.name,
      automaticNumberMappings: [
        DbMemberNumberMapping(
          deduplicatorName: "johndeduplicator",
          sourceNumbers: ["A76691"],
          targetNumber: "A123456",
          automatic: true,
        ),
      ],
      settings: RatingProjectSettings(
        algorithm: MultiplayerPercentEloRater(),
        memberNumberMappingBlacklist: {},
      )
    );

    var newRatings = await addMatchToTest(db, project, "data-entry-fix-user-mapped");
    var deduplicator = USPSADeduplicator();
    var deduplication = await deduplicator.deduplicateShooters(
      ratingProject: project,
      newRatings: newRatings,
      checkDataEntryErrors: true,
      group: ratingGroup,
    );

    expect(deduplication.isOk(), isTrue);
    var results = deduplication.unwrap();
    expect(reason: "number of results", results, hasLength(1));
    expect(reason: "number of causes", results[0].causes, hasLength(1));
    expect(reason: "cause is FixedInSettings", results[0].causes.first, isA<FixedInSettings>());
    expect(reason: "number of proposed actions", results[0].proposedActions, hasLength(1));
    expect(reason: "proposed action is PreexistingMapping", results[0].proposedActions.first, isA<PreexistingMapping>());
    var fix = results[0].proposedActions.first as PreexistingMapping;
    expect(reason: "target number", fix.targetNumber, equals("A123456"));
    expect(reason: "source number", fix.sourceNumber, equals("A76691"));
  });

  test("Pre-Blacklisted Similar Numbers", () async {
    var project = DbRatingProject(
      name: "DataEntryFix Pre-Blacklisted",
      sportName: uspsaSport.name,
      settings: RatingProjectSettings(
        algorithm: MultiplayerPercentEloRater(),
        memberNumberMappingBlacklist: {},
      )
    );

    project.settings.memberNumberMappingBlacklist["A123456"] = ["A123457"];
    project.settings.memberNumberMappingBlacklist["A123457"] = ["A123456"];

    var newRatings = await addMatchToTest(db, project, "data-entry-fix-pre-blacklisted");
    var deduplicator = USPSADeduplicator();
    var deduplication = await deduplicator.deduplicateShooters(
      ratingProject: project,
      newRatings: newRatings,
      checkDataEntryErrors: true,
      group: ratingGroup,
    );

    expect(deduplication.isOk(), isTrue);
    var results = deduplication.unwrap();
    expect(reason: "number of results", results, isEmpty);
  });

  test("Improvable UserMapping", () async {
    var project = DbRatingProject(
      name: "Improvable UserMapping",
      sportName: uspsaSport.name,
      settings: RatingProjectSettings(
        algorithm: MultiplayerPercentEloRater(),
        memberNumberMappingBlacklist: {},
        userMemberNumberMappings: {
          "A123456": "L1234",
        },
      )
    );

    var newRatings = await addMatchToTest(db, project, "improvable-user-mapping");
    var deduplicator = USPSADeduplicator();
    var deduplication = await deduplicator.deduplicateShooters(
      ratingProject: project,
      newRatings: newRatings,
      checkDataEntryErrors: true,
      group: ratingGroup,
    );

    expect(deduplication.isOk(), isTrue);
    var results = deduplication.unwrap();
    expect(reason: "number of results", results, hasLength(1));
    expect(reason: "number of causes", results[0].causes, isEmpty);
    expect(reason: "number of proposed actions", results[0].proposedActions, hasLength(1));
    expect(reason: "proposed action is UserMapping", results[0].proposedActions.first, isA<UserMapping>());
    var fix = results[0].proposedActions.first as UserMapping;
    expect(reason: "target number", fix.targetNumber, equals("B123"));
    expect(reason: "source numbers", fix.sourceNumbers, unorderedEquals(["A123456", "L1234"]));
  });

  test("Improvable AutoMapping", () async {
    var project = DbRatingProject(
      name: "Improvable AutoMapping",
      sportName: uspsaSport.name,
      automaticNumberMappings: [
        DbMemberNumberMapping(
          deduplicatorName: "johndeduplicator",
          sourceNumbers: ["A123456"],
          targetNumber: "L1234",
          automatic: true,
        ),
      ],
      settings: RatingProjectSettings(
        algorithm: MultiplayerPercentEloRater(),
        memberNumberMappingBlacklist: {},
      )
    );

    var newRatings = await addMatchToTest(db, project, "improvable-user-mapping");
    var deduplicator = USPSADeduplicator();
    var deduplication = await deduplicator.deduplicateShooters(
      ratingProject: project,
      newRatings: newRatings,
      checkDataEntryErrors: true,
      group: ratingGroup,
    );

    expect(deduplication.isOk(), isTrue);
    var results = deduplication.unwrap();
    expect(reason: "number of results", results, hasLength(1));
    expect(reason: "number of causes", results[0].causes, isEmpty);
    expect(reason: "number of proposed actions", results[0].proposedActions, hasLength(1));
    expect(reason: "proposed action is AutoMapping", results[0].proposedActions.first, isA<AutoMapping>());
    var fix = results[0].proposedActions.first as AutoMapping;
    expect(reason: "target number", fix.targetNumber, equals("B123"));
    expect(reason: "source numbers", fix.sourceNumbers, unorderedEquals(["A123456", "L1234"]));
  });

  test("Blacklisted AutoMapping 1", () async {
    var project = DbRatingProject(
      name: "Blacklisted AutoMapping 1",
      sportName: uspsaSport.name,
      settings: RatingProjectSettings(
        algorithm: MultiplayerPercentEloRater(),
        memberNumberMappingBlacklist: {
          "A123456": ["L1234"],
        },
      )
    );

    var newRatings = await addMatchToTest(db, project, "improvable-user-mapping");
    var deduplicator = USPSADeduplicator();
    var deduplication = await deduplicator.deduplicateShooters(
      ratingProject: project,
      newRatings: newRatings,
      checkDataEntryErrors: true,
      group: ratingGroup,
    );

    expect(deduplication.isOk(), isTrue);
    var results = deduplication.unwrap();
    expect(reason: "number of results", results, hasLength(1));
    expect(reason: "number of causes", results[0].causes, isEmpty);
    expect(reason: "number of proposed actions", results[0].proposedActions, hasLength(1));
    expect(reason: "proposed action is AutoMapping", results[0].proposedActions.first, isA<AutoMapping>());
    var fix = results[0].proposedActions.first as AutoMapping;
    expect(reason: "target number", fix.targetNumber, equals("B123"));
    expect(reason: "source numbers", fix.sourceNumbers, unorderedEquals(["A123456"]));
  });

  test("Blacklisted AutoMapping 2", () async {
    var project = DbRatingProject(
      name: "Blacklisted AutoMapping 2",
      sportName: uspsaSport.name,
      settings: RatingProjectSettings(
        algorithm: MultiplayerPercentEloRater(),
        memberNumberMappingBlacklist: {
          "A123456": ["L1234", "B123"],
          "L1234": ["B123"],
        },
      )
    );

    var newRatings = await addMatchToTest(db, project, "improvable-user-mapping");
    var deduplicator = USPSADeduplicator();
    var deduplication = await deduplicator.deduplicateShooters(
      ratingProject: project,
      newRatings: newRatings,
      checkDataEntryErrors: true,
      group: ratingGroup,
    );

    expect(deduplication.isOk(), isTrue);
    var results = deduplication.unwrap();
    expect(reason: "number of results", results, hasLength(1));
    expect(reason: "number of causes", results[0].causes, hasLength(1));
    expect(reason: "cause is AmbiguousMapping", results[0].causes.first, isA<FixedInSettings>());
    expect(reason: "number of proposed actions", results[0].proposedActions, isEmpty);
  });

  test("AutoMapping A->L", () async {
    var project = DbRatingProject(
      name: "AutoMapping A->L",
      sportName: uspsaSport.name,
      settings: RatingProjectSettings(
        algorithm: MultiplayerPercentEloRater(),
      )
    );

    var newRatings = await addMatchToTest(db, project, "auto-mapping-a-l");
    var deduplicator = USPSADeduplicator();
    var deduplication = await deduplicator.deduplicateShooters(
      ratingProject: project,
      newRatings: newRatings,
      checkDataEntryErrors: true,
      group: ratingGroup,
    );

    expect(deduplication.isOk(), isTrue);
    var results = deduplication.unwrap();
    expect(reason: "number of results", results, hasLength(1));
    expect(reason: "number of causes", results[0].causes, isEmpty);
    expect(reason: "number of proposed actions", results[0].proposedActions, hasLength(1));
    expect(reason: "proposed action is AutoMapping", results[0].proposedActions.first, isA<AutoMapping>());
    var fix = results[0].proposedActions.first as AutoMapping;
    expect(reason: "target number", fix.targetNumber, equals("L1234"));
    expect(reason: "source numbers", fix.sourceNumbers, unorderedEquals(["A123456"]));
  });

  test("AutoMapping A->RD", () async {
    var project = DbRatingProject(
      name: "AutoMapping A->L",
      sportName: uspsaSport.name,
      settings: RatingProjectSettings(
        algorithm: MultiplayerPercentEloRater(),
      )
    );

    var newRatings = await addMatchToTest(db, project, "auto-mapping-a-rd");
    var deduplicator = USPSADeduplicator();
    var deduplication = await deduplicator.deduplicateShooters(
      ratingProject: project,
      newRatings: newRatings,
      checkDataEntryErrors: true,
      group: ratingGroup,
    );

    expect(deduplication.isOk(), isTrue);
    var results = deduplication.unwrap();
    expect(reason: "number of results", results, hasLength(1));
    expect(reason: "number of causes", results[0].causes, isEmpty);
    expect(reason: "number of proposed actions", results[0].proposedActions, hasLength(1));
    expect(reason: "proposed action is AutoMapping", results[0].proposedActions.first, isA<AutoMapping>());
    var fix = results[0].proposedActions.first as AutoMapping;
    expect(reason: "target number", fix.targetNumber, equals("RD12"));
    expect(reason: "source numbers", fix.sourceNumbers, unorderedEquals(["A123456", "L1234", "B123"]));
  });

  test("AutoMapping L->RD", () async {
    var project = DbRatingProject(
      name: "AutoMapping L->RD",
      sportName: uspsaSport.name,
      settings: RatingProjectSettings(
        algorithm: MultiplayerPercentEloRater(),
      )
    );

    var newRatings = await addMatchToTest(db, project, "auto-mapping-l-rd");
    var deduplicator = USPSADeduplicator();
    var deduplication = await deduplicator.deduplicateShooters(
      ratingProject: project,
      newRatings: newRatings,
      checkDataEntryErrors: true,
      group: ratingGroup,
    );

    expect(deduplication.isOk(), isTrue);
    var results = deduplication.unwrap();
    expect(reason: "number of results", results, hasLength(1));
    expect(reason: "number of causes", results[0].causes, isEmpty);
    expect(reason: "number of proposed actions", results[0].proposedActions, hasLength(1));
    expect(reason: "proposed action is AutoMapping", results[0].proposedActions.first, isA<AutoMapping>());
    var fix = results[0].proposedActions.first as AutoMapping;
    expect(reason: "target number", fix.targetNumber, equals("RD12"));
    expect(reason: "source numbers", fix.sourceNumbers, unorderedEquals(["L1234"]));
  });

  test("AmbiguousMapping Resolvable", () async {
    var project = DbRatingProject(
      name: "AmbiguousMapping Resolvable",
      sportName: uspsaSport.name,
      settings: RatingProjectSettings(
        algorithm: MultiplayerPercentEloRater(),
      )
    );

    var newRatings = await addMatchToTest(db, project, "ambiguous-mapping-resolvable");
    var deduplicator = USPSADeduplicator();
    var deduplication = await deduplicator.deduplicateShooters(
      ratingProject: project,
      newRatings: newRatings,
      checkDataEntryErrors: true,
      group: ratingGroup,
    );

    expect(deduplication.isOk(), isTrue);
    var results = deduplication.unwrap();
    expect(reason: "number of results", results, hasLength(1));
    expect(reason: "number of causes", results[0].causes, hasLength(2));
    var multipleNumbersCause = results[0].causes.firstWhereOrNull((e) => e is MultipleNumbersOfType) as MultipleNumbersOfType;
    var ambiguousMappingCause = results[0].causes.firstWhereOrNull((e) => e is AmbiguousMapping) as AmbiguousMapping;
    expect(reason: "has multiple numbers cause", multipleNumbersCause, isNotNull);
    expect(reason: "has ambiguous mapping cause", ambiguousMappingCause, isNotNull);
    expect(reason: "number of proposed actions", results[0].proposedActions, hasLength(2));
    var dataEntryFix = results[0].proposedActions.firstWhereOrNull((e) => e is DataEntryFix) as DataEntryFix;
    var autoMapping = results[0].proposedActions.firstWhereOrNull((e) => e is AutoMapping) as AutoMapping;
    expect(reason: "has data entry fix", dataEntryFix, isNotNull);
    expect(reason: "has auto mapping", autoMapping, isNotNull);
    expect(reason: "data entry fix source number", dataEntryFix.sourceNumber, equals("A123457"));
    expect(reason: "data entry fix target number", dataEntryFix.targetNumber, equals("A123456"));
    expect(reason: "auto mapping target number", autoMapping.targetNumber, equals("L1234"));
    expect(reason: "auto mapping source numbers", autoMapping.sourceNumbers, unorderedEquals(["A123456"]));
  });

  test("AmbiguousMapping Unresolvable", () async {
    var project = DbRatingProject(
      name: "AmbiguousMapping Unresolvable",
      sportName: uspsaSport.name,
      settings: RatingProjectSettings(
        algorithm: MultiplayerPercentEloRater(),
      )
    );

    var newRatings = await addMatchToTest(db, project, "ambiguous-mapping-unresolvable");
    var deduplicator = USPSADeduplicator();
    var deduplication = await deduplicator.deduplicateShooters(
      ratingProject: project,
      newRatings: newRatings,
      checkDataEntryErrors: true,
      group: ratingGroup,
    );

    expect(deduplication.isOk(), isTrue);
    var results = deduplication.unwrap();
    expect(reason: "number of results", results, hasLength(1));
    expect(reason: "number of causes", results[0].causes, hasLength(2));
    var multipleNumbersCause = results[0].causes.firstWhereOrNull((e) => e is MultipleNumbersOfType) as MultipleNumbersOfType;
    var ambiguousMappingCause = results[0].causes.firstWhereOrNull((e) => e is AmbiguousMapping) as AmbiguousMapping;
    expect(reason: "has multiple numbers cause", multipleNumbersCause, isNotNull);
    expect(reason: "has ambiguous mapping cause", ambiguousMappingCause, isNotNull);
    expect(reason: "ambiguous mapping indicates source conflicts", ambiguousMappingCause.sourceConflicts, isTrue);
    expect(reason: "ambiguous mapping does not indicate target conflicts", ambiguousMappingCause.targetConflicts, isFalse);
    expect(reason: "ambiguous mapping has correct source numbers", ambiguousMappingCause.sourceNumbers, unorderedEquals(["A123456", "A76691"]));
    expect(reason: "ambiguous mapping has correct target numbers", ambiguousMappingCause.targetNumbers, unorderedEquals(["L1234"]));
    expect(reason: "ambiguous mapping has correct conflicting types", ambiguousMappingCause.conflictingTypes, unorderedEquals([MemberNumberType.standard]));
    expect(reason: "number of proposed actions", results[0].proposedActions, hasLength(1));
    var blacklist = results[0].proposedActions.firstWhereOrNull((e) => e is Blacklist) as Blacklist;
    expect(reason: "has blacklist", blacklist, isNotNull);
    var n1 = blacklist.sourceNumber;
    var n2 = blacklist.targetNumber;
    expect(reason: "blacklist numbers", [n1, n2], unorderedEquals(["A123456", "A76691"]));
  });

  test("AmbiguousMapping Resolvable 2", () async {
    var project = DbRatingProject(
      name: "AmbiguousMapping Resolvable 2",
      sportName: uspsaSport.name,
      settings: RatingProjectSettings(
        algorithm: MultiplayerPercentEloRater(),
      )
    );

    var newRatings = await addMatchToTest(db, project, "ambiguous-mapping-resolvable-2");
    var deduplicator = USPSADeduplicator();
    var deduplication = await deduplicator.deduplicateShooters(
      ratingProject: project,
      newRatings: newRatings,
      checkDataEntryErrors: true,
      group: ratingGroup,
    );

    expect(deduplication.isOk(), isTrue);
    var results = deduplication.unwrap();
    expect(reason: "number of results", results, hasLength(1));
    expect(reason: "number of causes", results[0].causes, hasLength(2));
    var multipleNumbersCause = results[0].causes.firstWhereOrNull((e) => e is MultipleNumbersOfType) as MultipleNumbersOfType;
    var ambiguousMappingCause = results[0].causes.firstWhereOrNull((e) => e is AmbiguousMapping) as AmbiguousMapping;
    expect(reason: "has multiple numbers cause", multipleNumbersCause, isNotNull);
    expect(reason: "has ambiguous mapping cause", ambiguousMappingCause, isNotNull);
    expect(reason: "number of proposed actions", results[0].proposedActions, hasLength(2));
    var dataEntryFix = results[0].proposedActions.firstWhereOrNull((e) => e is DataEntryFix) as DataEntryFix;
    var autoMapping = results[0].proposedActions.firstWhereOrNull((e) => e is AutoMapping) as AutoMapping;
    expect(reason: "has data entry fix", dataEntryFix, isNotNull);
    expect(reason: "has auto mapping", autoMapping, isNotNull);
    expect(reason: "data entry fix source number", dataEntryFix.sourceNumber, equals("L1235"));
    expect(reason: "data entry fix target number", dataEntryFix.targetNumber, equals("L1234"));
    expect(reason: "auto mapping target number", autoMapping.targetNumber, equals("L1234"));
    expect(reason: "auto mapping source numbers", autoMapping.sourceNumbers, unorderedEquals(["A123456"]));
  });

  test("AmbiguousMapping Unresolvable 2", () async {
    var project = DbRatingProject(
      name: "AmbiguousMapping Unresolvable 2",
      sportName: uspsaSport.name,
      settings: RatingProjectSettings(
        algorithm: MultiplayerPercentEloRater(),
      )
    );

    var newRatings = await addMatchToTest(db, project, "ambiguous-mapping-unresolvable-2");
    var deduplicator = USPSADeduplicator();
    var deduplication = await deduplicator.deduplicateShooters(
      ratingProject: project,
      newRatings: newRatings,
      checkDataEntryErrors: true,
      group: ratingGroup,
    );

    expect(deduplication.isOk(), isTrue);
    var results = deduplication.unwrap();
    expect(reason: "number of results", results, hasLength(1));
    expect(reason: "number of causes", results[0].causes, hasLength(2));
    var multipleNumbersCause = results[0].causes.firstWhereOrNull((e) => e is MultipleNumbersOfType) as MultipleNumbersOfType;
    var ambiguousMappingCause = results[0].causes.firstWhereOrNull((e) => e is AmbiguousMapping) as AmbiguousMapping;
    expect(reason: "has multiple numbers cause", multipleNumbersCause, isNotNull);
    expect(reason: "has ambiguous mapping cause", ambiguousMappingCause, isNotNull);
    expect(reason: "ambiguous mapping indicates source conflicts", ambiguousMappingCause.sourceConflicts, isFalse);
    expect(reason: "ambiguous mapping indicates target conflicts", ambiguousMappingCause.targetConflicts, isTrue);
    expect(reason: "ambiguous mapping has correct source numbers", ambiguousMappingCause.sourceNumbers, unorderedEquals(["A123456"]));
    expect(reason: "ambiguous mapping has correct target numbers", ambiguousMappingCause.targetNumbers, unorderedEquals(["L1234", "L5678"]));
    expect(reason: "ambiguous mapping has correct conflicting types", ambiguousMappingCause.conflictingTypes, unorderedEquals([MemberNumberType.life]));
  });

  test("Multiple Associate Numbers", () async {
    var project = DbRatingProject(
      name: "Multiple Associate Numbers",
      sportName: uspsaSport.name,
      settings: RatingProjectSettings(
        algorithm: MultiplayerPercentEloRater(),
      )
    );

    var newRatings = await addMatchToTest(db, project, "multiple-associate-numbers");
    var deduplicator = USPSADeduplicator();
    var deduplication = await deduplicator.deduplicateShooters(
      ratingProject: project,
      newRatings: newRatings,
      checkDataEntryErrors: true,
      group: ratingGroup,
    );

    expect(deduplication.isOk(), isTrue);
    var results = deduplication.unwrap();
    expect(reason: "number of results", results, isEmpty);
  });

  test("Simple No Prefix", () async {
    var project = DbRatingProject(
      name: "Simple No Prefix",
      sportName: uspsaSport.name,
      settings: RatingProjectSettings(
        algorithm: MultiplayerPercentEloRater(),
      )
    );

    var newRatings = await addMatchToTest(db, project, "simple-no-prefix");
    var deduplicator = USPSADeduplicator();
    var deduplication = await deduplicator.deduplicateShooters(
      ratingProject: project,
      newRatings: newRatings,
      checkDataEntryErrors: true,
      group: ratingGroup,
    );

    expect(deduplication.isOk(), isTrue);
    var results = deduplication.unwrap();
    expect(reason: "number of results", results, hasLength(1));
    var result = results.first;
    expect(reason: "number of proposed actions", result.proposedActions, hasLength(1));
    var dataEntryFix = result.proposedActions.firstWhereOrNull((e) => e is DataEntryFix) as DataEntryFix;
    expect(reason: "data entry fix source number", dataEntryFix.sourceNumber, equals("123456"));
    expect(reason: "data entry fix target number", dataEntryFix.targetNumber, equals("A123456"));
  });

  test("Complex No Prefix", () async {
    var project = DbRatingProject(
      name: "Complex No Prefix",
      sportName: uspsaSport.name,
      settings: RatingProjectSettings(
        algorithm: MultiplayerPercentEloRater(),
      )
    );

    var newRatings = await addMatchToTest(db, project, "complex-no-prefix");
    var deduplicator = USPSADeduplicator();
    var deduplication = await deduplicator.deduplicateShooters(
      ratingProject: project,
      newRatings: newRatings,
      checkDataEntryErrors: true,
      group: ratingGroup,
    );

    expect(deduplication.isOk(), isTrue);
    var results = deduplication.unwrap();
    expect(reason: "number of results", results, hasLength(1));
    var result = results.first;
    expect(reason: "number of proposed actions", result.proposedActions, hasLength(2));
    var dataEntryFix = result.proposedActions.firstWhereOrNull((e) => e is DataEntryFix) as DataEntryFix;
    expect(reason: "data entry fix source number", dataEntryFix.sourceNumber, equals("123456"));
    expect(reason: "data entry fix target number", dataEntryFix.targetNumber, equals("A123456"));
    var autoMapping = result.proposedActions.firstWhereOrNull((e) => e is AutoMapping) as AutoMapping;
    expect(reason: "auto mapping target number", autoMapping.targetNumber, equals("L1234"));
    expect(reason: "auto mapping source numbers", autoMapping.sourceNumbers, unorderedEquals(["A123456"]));
  });

  test("International to Standard", () async {
    var project = DbRatingProject(
      name: "International to Standard",
      sportName: uspsaSport.name,
      settings: RatingProjectSettings(
        algorithm: MultiplayerPercentEloRater(),
      )
    );

    var newRatings = await addMatchToTest(db, project, "international-to-standard");
    var deduplicator = USPSADeduplicator();
    var deduplication = await deduplicator.deduplicateShooters(
      ratingProject: project,
      newRatings: newRatings,
      checkDataEntryErrors: true,
      group: ratingGroup,
    );

    expect(deduplication.isOk(), isTrue);
    var results = deduplication.unwrap();
    expect(reason: "number of results", results, hasLength(1));
    var result = results.first;
    expect(reason: "number of proposed actions", result.proposedActions, hasLength(1));
    var dataEntryFix = result.proposedActions.firstWhereOrNull((e) => e is DataEntryFix) as DataEntryFix;
    expect(reason: "data entry fix source number", dataEntryFix.sourceNumber, equals("52410"));
    expect(reason: "data entry fix target number", dataEntryFix.targetNumber, equals("A124456"));
  });

  test("DataEntryFix Bad Associate", () async {
    var project = DbRatingProject(
      name: "DataEntryFix Bad Associate",
      sportName: uspsaSport.name,
      settings: RatingProjectSettings(
        algorithm: MultiplayerPercentEloRater(),
      )
    );

    var newRatings = await addMatchToTest(db, project, "data-entry-fix-bad-associate");
    var deduplicator = USPSADeduplicator();
    var deduplication = await deduplicator.deduplicateShooters(
      ratingProject: project,
      newRatings: newRatings,
      checkDataEntryErrors: true,
      group: ratingGroup,
    );

    expect(deduplication.isOk(), isTrue);
    var results = deduplication.unwrap();
    expect(reason: "number of results", results, hasLength(1));
    var result = results.first;
    expect(reason: "number of proposed actions", result.proposedActions, hasLength(1));
    var dataEntryFix = result.proposedActions.firstWhereOrNull((e) => e is DataEntryFix) as DataEntryFix;
    expect(reason: "data entry fix source number", dataEntryFix.sourceNumber, equals("TY123456L"));
    expect(reason: "data entry fix target number", dataEntryFix.targetNumber, equals("A123456"));
  });

  test("DataEntryFix Bad Life", () async {
    var project = DbRatingProject(
      name: "DataEntryFix Bad Life",
      sportName: uspsaSport.name,
      settings: RatingProjectSettings(
        algorithm: MultiplayerPercentEloRater(),
      )
    );

    var newRatings = await addMatchToTest(db, project, "data-entry-fix-bad-life");
    var deduplicator = USPSADeduplicator();
    var deduplication = await deduplicator.deduplicateShooters(
      ratingProject: project,
      newRatings: newRatings,
      checkDataEntryErrors: true,
      group: ratingGroup,
    );

    expect(deduplication.isOk(), isTrue);
    var results = deduplication.unwrap();
    expect(reason: "number of results", results, hasLength(1));
    var result = results.first;
    expect(reason: "number of proposed actions", result.proposedActions, hasLength(1));
    var dataEntryFix = result.proposedActions.firstWhereOrNull((e) => e is DataEntryFix) as DataEntryFix;
    expect(reason: "data entry fix source number", dataEntryFix.sourceNumber, equals("L12"));
    expect(reason: "data entry fix target number", dataEntryFix.targetNumber, equals("L1234"));
  });

  test("DataEntryFix Bad Benefactor", () async {
    var project = DbRatingProject(
      name: "DataEntryFix Bad Benefactor",
      sportName: uspsaSport.name,
      settings: RatingProjectSettings(
        algorithm: MultiplayerPercentEloRater(),
      )
    );

    var newRatings = await addMatchToTest(db, project, "data-entry-fix-bad-benefactor");
    var deduplicator = USPSADeduplicator();
    var deduplication = await deduplicator.deduplicateShooters(
      ratingProject: project,
      newRatings: newRatings,
      checkDataEntryErrors: true,
      group: ratingGroup,
    );

    expect(deduplication.isOk(), isTrue);
    var results = deduplication.unwrap();
    expect(reason: "number of results", results, hasLength(1));
    var result = results.first;
    expect(reason: "number of proposed actions", result.proposedActions, hasLength(1));
    var dataEntryFix = result.proposedActions.firstWhereOrNull((e) => e is DataEntryFix) as DataEntryFix;
    expect(reason: "data entry fix source number", dataEntryFix.sourceNumber, equals("B1234"));
    expect(reason: "data entry fix target number", dataEntryFix.targetNumber, equals("B123"));
  });

  test("Invalid Number DataEntryFix", () async {
    var project = DbRatingProject(
      name: "Invalid Number DataEntryFix",
      sportName: uspsaSport.name,
      settings: RatingProjectSettings(
        algorithm: MultiplayerPercentEloRater(),
      )
    );

    var newRatings = await addMatchToTest(db, project, "invalid-number-data-entry-fix");
    var deduplicator = USPSADeduplicator();
    var deduplication = await deduplicator.deduplicateShooters(
      ratingProject: project,
      newRatings: newRatings,
      checkDataEntryErrors: true,
      group: ratingGroup,
    );

    expect(deduplication.isOk(), isTrue);
    var results = deduplication.unwrap();
    expect(reason: "number of results", results, hasLength(1));
    var result = results.first;
    expect(reason: "number of causes", result.causes, hasLength(1));
    var cause = result.causes.first;
    expect(reason: "cause is MultipleNumbersOfType", cause is MultipleNumbersOfType, isTrue);
    var multipleNumbersOfType = cause as MultipleNumbersOfType;
    expect(reason: "member number type", multipleNumbersOfType.memberNumberType, equals(MemberNumberType.standard));
    expect(reason: "detected ABCD invalid", multipleNumbersOfType.probablyInvalidNumbers, equals(["ABCD"]));
    expect(reason: "can resolve automatically", multipleNumbersOfType.canResolveAutomatically, isTrue);
    expect(reason: "number of proposed actions", result.proposedActions, hasLength(1));
    var dataEntryFix = result.proposedActions.firstWhereOrNull((e) => e is DataEntryFix) as DataEntryFix;
    expect(reason: "data entry fix source number", dataEntryFix.sourceNumber, equals("ABCD"));
    expect(reason: "data entry fix target number", dataEntryFix.targetNumber, equals("A123456"));
  });

  test("Invalid Number DataEntryFix 2", () async {
    // Differs from the above in that this one would have selected the invalid number
    // as the target (it's 'older', i.e. earlier in the test data).
    var project = DbRatingProject(
      name: "Invalid Number DataEntryFix 2",
      sportName: uspsaSport.name,
      settings: RatingProjectSettings(
        algorithm: MultiplayerPercentEloRater(),
      )
    );

    var newRatings = await addMatchToTest(db, project, "invalid-number-data-entry-fix-2");
    var deduplicator = USPSADeduplicator();
    var deduplication = await deduplicator.deduplicateShooters(
      ratingProject: project,
      newRatings: newRatings,
      checkDataEntryErrors: true,
      group: ratingGroup,
    );

    expect(deduplication.isOk(), isTrue);
    var results = deduplication.unwrap();
    expect(reason: "number of results", results, hasLength(1));
    var result = results.first;
    expect(reason: "number of causes", result.causes, hasLength(1));
    var cause = result.causes.first;
    expect(reason: "cause is MultipleNumbersOfType", cause, isA<MultipleNumbersOfType>());
    var multipleNumbersOfType = cause as MultipleNumbersOfType;
    expect(reason: "member number type", multipleNumbersOfType.memberNumberType, equals(MemberNumberType.standard));
    expect(reason: "detected ABCD invalid", multipleNumbersOfType.probablyInvalidNumbers, equals(["ABCD"]));
    expect(reason: "can resolve automatically", multipleNumbersOfType.canResolveAutomatically, isTrue);
    expect(reason: "number of proposed actions", result.proposedActions, hasLength(1));
    var dataEntryFix = result.proposedActions.firstWhereOrNull((e) => e is DataEntryFix) as DataEntryFix;
    expect(reason: "data entry fix source number", dataEntryFix.sourceNumber, equals("ABCD"));
    expect(reason: "data entry fix target number", dataEntryFix.targetNumber, equals("A123456"));
  });

  test("Corrected Ambiguous Mapping", () async {
    var project = DbRatingProject(
      name: "Corrected Ambiguous Mapping",
      sportName: uspsaSport.name,
      settings: RatingProjectSettings(
        algorithm: MultiplayerPercentEloRater(),
        userMemberNumberMappings: {
          "FY88787": "L6166",
        },
        memberNumberMappingBlacklist: {
          "TY7057": ["FY88787", "L6166"],
          "L6166": ["TY7057"],
          "FY88787": ["TY7057"],
        }
      )
    );

    var newRatings = await addMatchToTest(db, project, "corrected-ambiguous-mapping");
    var deduplicator = USPSADeduplicator();
    var deduplication = await deduplicator.deduplicateShooters(
      ratingProject: project,
      newRatings: newRatings,
      checkDataEntryErrors: true,
      group: ratingGroup,
    );

    expect(deduplication.isOk(), isTrue);
    var results = deduplication.unwrap();
    expect(reason: "number of results", results, hasLength(1));
    var result = results.first;
    expect(reason: "number of causes", result.causes, hasLength(1));
    expect(reason: "cause is FixedInSettings", result.causes.first, isA<FixedInSettings>());
  });


    test("Literal NOTAMEMBER -> Associate", () async {
    var project = DbRatingProject(
      name: "Literal NOTAMEMBER -> Associate",
      sportName: uspsaSport.name,
      settings: RatingProjectSettings(
        algorithm: MultiplayerPercentEloRater(),
      )
    );

    var newRatings = await addMatchToTest(db, project, "notamember-to-associate");
    var deduplicator = USPSADeduplicator();
    var deduplication = await deduplicator.deduplicateShooters(
      ratingProject: project,
      newRatings: newRatings,
      checkDataEntryErrors: true,
      group: ratingGroup,
    );

    expect(deduplication.isOk(), isTrue);
    var results = deduplication.unwrap();
    expect(reason: "number of results", results, hasLength(1));
    var result = results.first;
    expect(reason: "number of causes", result.causes, hasLength(1));
    expect(reason: "cause is MultipleNumbersOfType", result.causes.first, isA<MultipleNumbersOfType>());
    var multipleNumbersOfType = result.causes.first as MultipleNumbersOfType;
    expect(reason: "member number type", multipleNumbersOfType.memberNumberType, equals(MemberNumberType.standard));
    expect(reason: "detected NOTAMEMBER invalid", multipleNumbersOfType.probablyInvalidNumbers, equals(["NOTAMEMBER"]));
    expect(reason: "can resolve automatically", multipleNumbersOfType.canResolveAutomatically, isTrue);
    expect(reason: "number of proposed actions", result.proposedActions, hasLength(1));
    expect(reason: "proposed action is DataEntryFix", result.proposedActions.first, isA<DataEntryFix>());
    var dataEntryFix = result.proposedActions.first as DataEntryFix;
    expect(reason: "data entry fix source number", dataEntryFix.sourceNumber, equals("NOTAMEMBER"));
    expect(reason: "data entry fix target number", dataEntryFix.targetNumber, equals("A123456"));
  });

  test("Multiple International Standard Numbers", () async {
    var project = DbRatingProject(
      name: "Multiple International Standard Numbers",
      sportName: uspsaSport.name,
      settings: RatingProjectSettings(
        algorithm: MultiplayerPercentEloRater(),
      )
    );

    var newRatings = await addMatchToTest(db, project, "multiple-international-standard-numbers");
    var deduplicator = USPSADeduplicator();
    var deduplication = await deduplicator.deduplicateShooters(
      ratingProject: project,
      newRatings: newRatings,
      checkDataEntryErrors: true,
      group: ratingGroup,
    );

    expect(deduplication.isOk(), isTrue);
    var results = deduplication.unwrap();
    expect(reason: "number of results", results, isEmpty);
  });

  test("Mark Miller Already Added Ambiguous Mapping", () async {
    var project = DbRatingProject(
      name: "Mark Miller Already Added Ambiguous Mapping",
      sportName: uspsaSport.name,
      settings: RatingProjectSettings(
        algorithm: MultiplayerPercentEloRater(),
        userMemberNumberMappings: {
          "FY88788": "L6166",
        },
        memberNumberMappingBlacklist: {
          "TY7057": ["FY88788", "L6166"],
          "L6166": ["TY7057"],
          "FY88788": ["TY7057"],
        }
      )
    );

    var newRatings = await addMatchToTest(db, project, "mark-miller-already-added-ambiguous-mapping");
    var deduplicator = USPSADeduplicator();
    var deduplication = await deduplicator.deduplicateShooters(
      ratingProject: project,
      newRatings: newRatings,
      checkDataEntryErrors: true,
      group: ratingGroup,
    );

    expect(deduplication.isOk(), isTrue);
    var results = deduplication.unwrap();
    expect(reason: "number of results", results, isEmpty);
  });

  test("Michael Morgan Ambiguous Mapping", () async {
    // In this case, we have a known mapping from FY94000 to B96, and a blacklist
    // from A163595 to FY94000. Since we know that FY94000 is B96, we shouldn't
    // need an explicit blacklist entry for A163595 -> B96.
    var project = DbRatingProject(
      name: "Michael Morgan Ambiguous Mapping",
      sportName: uspsaSport.name,
      settings: RatingProjectSettings(
        algorithm: MultiplayerPercentEloRater(),
        userMemberNumberMappings: {
          "FY94000": "B96",
        },
        memberNumberMappingBlacklist: {
          "A163595": ["FY94000"],
        }
      )
    );

    var newRatings = await addMatchToTest(db, project, "michael-morgan-ambiguous-mapping");
    var deduplicator = USPSADeduplicator();
    var deduplication = await deduplicator.deduplicateShooters(
      ratingProject: project,
      newRatings: newRatings,
      checkDataEntryErrors: true,
      group: ratingGroup,
    );

    expect(deduplication.isOk(), isTrue);
    var results = deduplication.unwrap();
    expect(reason: "number of results", results, hasLength(1));
    var result = results.first;
    var cause = result.causes.first;
    expect(reason: "cause is FixedInSettings", cause, isA<FixedInSettings>());
    var proposedActions = result.proposedActions;
    expect(reason: "number of proposed actions", proposedActions, hasLength(2));
    var preexistingMapping = proposedActions.firstWhereOrNull((e) => e is PreexistingMapping) as PreexistingMapping;
    expect(reason: "preexisting mapping", preexistingMapping, isNotNull);
    expect(reason: "preexisting mapping source number", preexistingMapping.sourceNumber, equals("FY94000"));
    expect(reason: "preexisting mapping target number", preexistingMapping.targetNumber, equals("B96"));
    var preexistingBlacklist = proposedActions.firstWhereOrNull((e) => e is PreexistingBlacklist) as PreexistingBlacklist;
    expect(reason: "preexisting blacklist", preexistingBlacklist, isNotNull);
    expect(reason: "preexisting blacklist source number", preexistingBlacklist.sourceNumber, equals("A163595"));
    expect(reason: "preexisting blacklist target number", preexistingBlacklist.targetNumber, equals("FY94000"));
  });

  // #endregion
}

Future<List<DbShooterRating>> addMatchToTest(AnalystDatabase db, DbRatingProject project, String matchId) async {
  var dbMatch = await db.getMatchByAnySourceId([matchId]);
  project.matchPointers.add(MatchPointer.fromDbMatch(dbMatch!));

  await db.saveRatingProject(project);
  var match = dbMatch.hydrate().unwrap();

  List<DbShooterRating> newRatings = [];
  for(var competitor in match.shooters) {
    var r = DbShooterRating(
      sportName: uspsaSport.name,
      firstName: competitor.firstName,
      lastName: competitor.lastName,
      rating: 1000,
      memberNumber: competitor.memberNumber,
      female: competitor.female,
      error: 0,
      connectivity: 0,
      rawConnectivity: 0,
      firstSeen: match.date,
      lastSeen: match.date,
    );
    r.copyVitalsFrom(competitor);
    newRatings.add(r);
  }

  return newRatings;
}


Future<void> setupTestDb(AnalystDatabase db) async {
  db.isar.writeTxn(() async {
    await db.isar.clear();
  });

  var competitorMap = generateCompetitors();

  var simpleDataEntryMatch = generateMatch(
    shooters: [competitorMap["A123456"]!, competitorMap["A123457"]!],
    date: DateTime(2024, 1, 1),
    matchName: "Simple DataEntryFix",
    matchId: "data-entry-fix-similar-numbers",
  );

  var simpleBlacklistMatch = generateMatch(
    shooters: [competitorMap["A123456"]!, competitorMap["A76691"]!],
    date: DateTime(2024, 1, 7),
    matchName: "Simple Blacklist",
    matchId: "data-entry-fix-dissimilar-numbers",
  );

  var simpleAutoMappingMatch = generateMatch(
    shooters: [competitorMap["A123456"]!, competitorMap["L1234"]!],
    date: DateTime(2024, 1, 14),
    matchName: "Simple AutoMapping A->L",
    matchId: "auto-mapping-a-l",
  );

  var simpleAutoMappingMatch2 = generateMatch(
    shooters: [competitorMap["A123456"]!, competitorMap["L1234"]!, competitorMap["B123"]!, competitorMap["RD12"]!],
    date: DateTime(2024, 1, 21),
    matchName: "Simple AutoMapping A->RD",
    matchId: "auto-mapping-a-rd",
  );

  var simpleAutoMappingMatch3 = generateMatch(
    shooters: [competitorMap["L1234"]!, competitorMap["RD12"]!],
    date: DateTime(2024, 1, 28),
    matchName: "Simple AutoMapping L->RD",
    matchId: "auto-mapping-l-rd",
  );

  var simpleAmbiguousMappingMatch = generateMatch(
    shooters: [competitorMap["A123456"]!, competitorMap["A123457"]!, competitorMap["L1234"]!],
    date: DateTime(2024, 2, 1),
    matchName: "AmbiguousMapping Resolvable",
    matchId: "ambiguous-mapping-resolvable",
  );

  var simpleAmbiguousMappingUnresolvableMatch = generateMatch(
    shooters: [competitorMap["A123456"]!, competitorMap["A76691"]!, competitorMap["L1234"]!],
    date: DateTime(2024, 2, 7),
    matchName: "AmbiguousMapping Unresolvable",
    matchId: "ambiguous-mapping-unresolvable",
  );

  var simpleAmbiguousMappingResolvableMatch2 = generateMatch(
    shooters: [competitorMap["A123456"]!, competitorMap["L1234"]!, competitorMap["L1235"]!],
    date: DateTime(2024, 2, 7),
    matchName: "AmbiguousMapping Resolvable 2",
    matchId: "ambiguous-mapping-resolvable-2",
  );

  var simpleAmbiguousMappingUnresolvableMatch2 = generateMatch(
    shooters: [competitorMap["A123456"]!, competitorMap["L5678"]!, competitorMap["L1234"]!],
    date: DateTime(2024, 2, 7),
    matchName: "AmbiguousMapping Unresolvable 2",
    matchId: "ambiguous-mapping-unresolvable-2",
  );

  var dataEntryFixPreBlacklistedMatch = generateMatch(
    shooters: [competitorMap["A123456"]!, competitorMap["A123457"]!],
    date: DateTime(2024, 2, 14),
    matchName: "DataEntryFix Pre-Blacklisted",
    matchId: "data-entry-fix-pre-blacklisted",
  );

  var dataEntryFixUserMappedMatch = generateMatch(
    shooters: [competitorMap["A123456"]!, competitorMap["A76691"]!],
    date: DateTime(2024, 2, 21),
    matchName: "DataEntryFix User-Mapped",
    matchId: "data-entry-fix-user-mapped",
  );

  var resolvableCrossMappingMatch = generateMatch(
    shooters: [competitorMap["A123456"]!, competitorMap["L1234"]!, competitorMap["B123"]!],
    date: DateTime(2024, 2, 28),
    matchName: "Resolvable Cross Mapping",
    matchId: "resolvable-cross-mapping",
  );

  var resolvableCrossMappingMatch2 = generateMatch(
    shooters: [competitorMap["A123456"]!, competitorMap["L1234"]!, competitorMap["L1235"]!],
    date: DateTime(2024, 3, 7),
    matchName: "Resolvable Cross Mapping 2",
    matchId: "resolvable-cross-mapping-2",
  );

  var improvableUserMappingMatch = generateMatch(
    shooters: [competitorMap["A123456"]!, competitorMap["L1234"]!, competitorMap["B123"]!],
    date: DateTime(2024, 3, 14),
    matchName: "Improvable User Mapping",
    matchId: "improvable-user-mapping",
  );

  var multipleAssociateNumbersMatch = generateMatch(
    shooters: [competitorMap["A123456"]!, competitorMap["TY123456"]!, competitorMap["FY123456"]!],
    date: DateTime(2024, 3, 21),
    matchName: "Multiple Associate Numbers",
    matchId: "multiple-associate-numbers",
  );

  var simpleNoPrefixMatch = generateMatch(
    shooters: [competitorMap["123456"]!, competitorMap["A123456"]!],
    date: DateTime(2024, 3, 28),
    matchName: "Simple No Prefix",
    matchId: "simple-no-prefix",
  );

  var complexNoPrefixMatch = generateMatch(
    shooters: [competitorMap["123456"]!, competitorMap["A123456"]!, competitorMap["L1234"]!],
    date: DateTime(2024, 4, 1),
    matchName: "Complex No Prefix",
    matchId: "complex-no-prefix",
  );

  var internationalToStandardMatch = generateMatch(
    shooters: [competitorMap["52410"]!, competitorMap["A124456"]!],
    date: DateTime(2024, 4, 7),
    matchName: "International to Standard",
    matchId: "international-to-standard",
  );

  var dataEntryFixBadAssociateMatch = generateMatch(
    shooters: [competitorMap["TY123456L"]!, competitorMap["A123456"]!,],
    date: DateTime(2024, 4, 14),
    matchName: "DataEntryFix Bad Associate",
    matchId: "data-entry-fix-bad-associate",
  );

  var dataEntryFixBadAssociateMatch2 = generateMatch(
    shooters: [competitorMap["TY1234"]!, competitorMap["A123456"]!,],
    date: DateTime(2024, 4, 21),
    matchName: "DataEntryFix Bad Associate 2",
    matchId: "data-entry-fix-bad-associate-2",
  );

  var dataEntryFixBadLifeMatch = generateMatch(
    shooters: [competitorMap["L12"]!, competitorMap["L1234"]!,],
    date: DateTime(2024, 4, 28),
    matchName: "DataEntryFix Bad Life",
    matchId: "data-entry-fix-bad-life",
  );

  var dataEntryFixBadBenefactorMatch = generateMatch(
    shooters: [competitorMap["B1234"]!, competitorMap["B123"]!,],
    date: DateTime(2024, 5, 1),
    matchName: "DataEntryFix Bad Benefactor",
    matchId: "data-entry-fix-bad-benefactor",
  );

  var invalidNumberDataEntryFixMatch = generateMatch(
    shooters: [competitorMap["A123456"]!, competitorMap["ABCD"]!],
    date: DateTime(2024, 5, 7),
    matchName: "Invalid Number DataEntryFix",
    matchId: "invalid-number-data-entry-fix",
  );

  var invalidNumberDataEntryFixMatch2 = generateMatch(
    shooters: [competitorMap["ABCD"]!, competitorMap["A123456"]!],
    date: DateTime(2024, 5, 14),
    matchName: "Invalid Number DataEntryFix 2",
    matchId: "invalid-number-data-entry-fix-2",
  );

  var markMillerMatch = generateMatch(
    shooters: [competitorMap["FY88787"]!, competitorMap["TY7057"]!, competitorMap["L6166"]!],
    date: DateTime(2024, 5, 21),
    matchName: "Corrected Ambiguous Mapping",
    matchId: "corrected-ambiguous-mapping",
  );

  var notAMemberNumberMatch = generateMatch(
    shooters: [competitorMap["NOTAMEMBER"]!, competitorMap["A123456"]!],
    date: DateTime(2024, 5, 28),
    matchName: "Literal NOTAMEMBER -> Associate",
    matchId: "notamember-to-associate",
  );

  var multipleInternationalStandardNumbersMatch = generateMatch(
    shooters: [competitorMap["F97321"]!, competitorMap["TYF97321"]!],
    date: DateTime(2024, 6, 1),
    matchName: "Multiple International Standard Numbers",
    matchId: "multiple-international-standard-numbers",
  );

  var markMillerAlreadyAddedAmbiguousMappingMatch = generateMatch(
    shooters: [competitorMap["FY88788"]!, competitorMap["TY7057"]!],
    date: DateTime(2024, 6, 7),
    matchName: "Mark Miller Already Added Ambiguous Mapping",
    matchId: "mark-miller-already-added-ambiguous-mapping",
  );

  var michaelMorganAmbiguousMappingMatch = generateMatch(
    shooters: [competitorMap["FY94000"]!, competitorMap["A163595"]!, competitorMap["B96"]!],
    date: DateTime(2024, 6, 14),
    matchName: "Michael Morgan Ambiguous Mapping",
    matchId: "michael-morgan-ambiguous-mapping",
  );

  var futures = [
    db.saveMatch(simpleDataEntryMatch),
    db.saveMatch(simpleBlacklistMatch),
    db.saveMatch(simpleAutoMappingMatch),
    db.saveMatch(simpleAutoMappingMatch2),
    db.saveMatch(simpleAutoMappingMatch3),
    db.saveMatch(simpleAmbiguousMappingMatch),
    db.saveMatch(simpleAmbiguousMappingUnresolvableMatch),
    db.saveMatch(simpleAmbiguousMappingResolvableMatch2),
    db.saveMatch(simpleAmbiguousMappingUnresolvableMatch2),
    db.saveMatch(dataEntryFixPreBlacklistedMatch),
    db.saveMatch(dataEntryFixUserMappedMatch),
    db.saveMatch(resolvableCrossMappingMatch),
    db.saveMatch(resolvableCrossMappingMatch2),
    db.saveMatch(improvableUserMappingMatch),
    db.saveMatch(multipleAssociateNumbersMatch),
    db.saveMatch(simpleNoPrefixMatch),
    db.saveMatch(complexNoPrefixMatch),
    db.saveMatch(internationalToStandardMatch),
    db.saveMatch(dataEntryFixBadAssociateMatch),
    db.saveMatch(dataEntryFixBadAssociateMatch2),
    db.saveMatch(dataEntryFixBadLifeMatch),
    db.saveMatch(dataEntryFixBadBenefactorMatch),
    db.saveMatch(invalidNumberDataEntryFixMatch),
    db.saveMatch(invalidNumberDataEntryFixMatch2),
    db.saveMatch(markMillerMatch),
    db.saveMatch(notAMemberNumberMatch),
    db.saveMatch(multipleInternationalStandardNumbersMatch),
    db.saveMatch(markMillerAlreadyAddedAmbiguousMappingMatch),
    db.saveMatch(michaelMorganAmbiguousMappingMatch),
  ];
  await Future.wait(futures);
}

/// Generates a list of competitors useful for deduplication testing.
Map<String, Shooter> generateCompetitors() {
  Map<String, Shooter> competitors = {};

  // John Deduplicator, first through many-th of his name
  competitors["A123456"] = Shooter(
    firstName: "John",
    lastName: "Deduplicator",
    memberNumber: "A123456",
  );
  competitors["123456"] = Shooter(
    firstName: "John",
    lastName: "Deduplicator",
    memberNumber: "123456",
  );
  competitors["TY123456"] = Shooter(
    firstName: "John",
    lastName: "Deduplicator",
    memberNumber: "TY123456",
  );
  competitors["TY123456L"] = Shooter(
    firstName: "John",
    lastName: "Deduplicator",
    memberNumber: "TY123456L",
  );
  // why do people do this?
  competitors["ABCD"] = Shooter(
    firstName: "John",
    lastName: "Deduplicator",
    memberNumber: "ABCD",
  );
  competitors["NOTAMEMBER"] = Shooter(
    firstName: "John",
    lastName: "Deduplicator",
    memberNumber: "NOTAMEMBER",
  );
  competitors["TY1234"] = Shooter(
    firstName: "John",
    lastName: "Deduplicator",
    memberNumber: "TY1234",
  );
  competitors["L12"] = Shooter(
    firstName: "John",
    lastName: "Deduplicator",
    memberNumber: "L12",
  );
  competitors["B1234"] = Shooter(
    firstName: "John",
    lastName: "Deduplicator",
    memberNumber: "B1234",
  );
  competitors["FY123456"] = Shooter(
    firstName: "John",
    lastName: "Deduplicator",
    memberNumber: "FY123456",
  );
  // A typo
  competitors["A123457"] = Shooter(
    firstName: "John",
    lastName: "Deduplicator",
    memberNumber: "A123457",
  );
  // A life number
  competitors["L1234"] = Shooter(
    firstName: "John",
    lastName: "Deduplicator",
    memberNumber: "L1234",
  );
  // A typo
    competitors["L1235"] = Shooter(
    firstName: "John",
    lastName: "Deduplicator",
    memberNumber: "L1235",
  );
  // Benefactor and region director
  competitors["B123"] = Shooter(
    firstName: "John",
    lastName: "Deduplicator",
    memberNumber: "B123",
  );
  competitors["RD12"] = Shooter(
    firstName: "John",
    lastName: "Deduplicator",
    memberNumber: "RD12",
  );

  /// An unrelated John Deduplicator
  competitors["A76691"] = Shooter(
    firstName: "John",
    lastName: "Deduplicator",
    memberNumber: "A76691",
  );

  /// Another unrelated John Deduplicator

  /// Another unrelated John Deduplicator
  competitors["L5678"] = Shooter(
    firstName: "John",
    lastName: "Deduplicator",
    memberNumber: "L5678",
  );

  // A Canadian Vaughn Deduplicator.
  competitors["52410"] = Shooter(
    firstName: "Vaughn",
    lastName: "Deduplicator",
    memberNumber: "52410",
  );
  competitors["A124456"] = Shooter(
    firstName: "Vaughn",
    lastName: "Deduplicator",
    memberNumber: "A124456",
  );
  competitors["F97321"] = Shooter(
    firstName: "Vaughn",
    lastName: "Deduplicator",
    memberNumber: "F97321",
  );
  competitors["TYF97321"] = Shooter(
    firstName: "Vaughn",
    lastName: "Deduplicator",
    memberNumber: "TYF97321",
  );

  // Mark Millers
  competitors["FY88787"] = Shooter(
    firstName: "Mark",
    lastName: "Miller",
    memberNumber: "FY88787",
  );
  competitors["TY7057"] = Shooter(
    firstName: "Mark",
    lastName: "Miller",
    memberNumber: "TY7057",
  );
  competitors["L6166"] = Shooter(
    firstName: "Mark",
    lastName: "Miller",
    memberNumber: "L6166",
  );

  // Mark Millers (mapping applied at shooter add)
  competitors["FY88788"] = Shooter(
    firstName: "Mark",
    lastName: "Miller",
    memberNumber: "FY88788",
  );
  competitors["FY88788"]!.memberNumber = "L6166";

  competitors["TY7058"] = Shooter(
    firstName: "Mark",
    lastName: "Miller",
    memberNumber: "TY7058",
  );

  // Michael Morgans (preexisting mapping from FY to B, blacklist from A to FY)
  competitors["FY94000"] = Shooter(
    firstName: "Michael",
    lastName: "Morgan",
    memberNumber: "FY94000",
  );
  competitors["A163595"] = Shooter(
    firstName: "Michael",
    lastName: "Morgan",
    memberNumber: "A163595",
  );
  competitors["B96"] = Shooter(
    firstName: "Michael",
    lastName: "Morgan",
    memberNumber: "B96",
  );

  return competitors;
}

ShootingMatch generateMatch({required List<Shooter> shooters, int stageCount = 5, String matchName = "Test Match", required DateTime date, String? matchId}) {
  var r = Random();
  var stages = List.generate(stageCount, (index) {
    int roundCount = r.nextInt(20) + 12;
    return MatchStage(
      stageId: index + 1, name: "Stage ${index + 1}", scoring: HitFactorScoring(),
      minRounds: roundCount, maxPoints: roundCount * 5,
    );
  });

  var entries = List.generate(shooters.length, (index) {
    var shooter = shooters[index];

    Map<MatchStage, RawScore> scores = {};

    for(var stage in stages) {
      Map<ScoringEvent, int> hitCounts = {};
      for(int i = 0; i < stage.minRounds; i++) {
        int hitDie = r.nextInt(100);
        if(hitDie > 10) {
          hitCounts.increment(uspsaMinorPF.targetEvents.lookupByName("A")!);
        }
        else if(hitDie > 5) {
          hitCounts.increment(uspsaMinorPF.targetEvents.lookupByName("C")!);
        }
        else if(hitDie > 3) {
          hitCounts.increment(uspsaMinorPF.targetEvents.lookupByName("D")!);
        }
        else if(hitDie > 0) {
          hitCounts.increment(uspsaMinorPF.targetEvents.lookupByName("M")!);
        }
        else {
          hitCounts.increment(uspsaMinorPF.targetEvents.lookupByName("NS")!);
        }
      }

      // Time is between 0.4 and 0.6 times the number of rounds.
      var time = stage.minRounds * 0.5 * (1 - ((r.nextDouble() - 0.5) * 0.2));

      scores[stage] = RawScore(
        scoring: stage.scoring,
        targetEvents: hitCounts,
        rawTime: time,
      );
    }

    var entry = MatchEntry(
      entryId: index,
      division: uspsaOpen,
      firstName: shooter.firstName,
      lastName: shooter.lastName,
      powerFactor: uspsaMinorPF,
      scores: scores,
    );

    entry.copyVitalsFrom(shooter);

    return entry;
  });

  var match = ShootingMatch(
    stages: stages,
    name: matchName,
    rawDate: date.toIso8601String(),
    date: date,
    sport: uspsaSport,
    shooters: entries,
    sourceIds: [matchId ?? Uuid().v4()],
    sourceCode: "test-autogen",
  );

  return match;
}
