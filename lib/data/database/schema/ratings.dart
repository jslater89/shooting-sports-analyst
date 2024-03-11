/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:convert';

import 'package:isar/isar.dart';
import 'package:shooting_sports_analyst/data/database/schema/match.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_system.dart';
import 'package:shooting_sports_analyst/data/ranking/project_manager.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/registry.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/shooter.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';

part 'ratings.g.dart';

// DbRatingProject hasMany DbRatingGroups hasMany DbShooterRatings hasMany DbRatingEvents.

mixin DbSportEntity {
  String get sportName;

  @ignore
  Sport get sport => SportRegistry().lookup(sportName)!;
}

@collection
class DbRatingProject with DbSportEntity {
  Id id = Isar.autoIncrement;

  String sportName;

  // Settings
  @Index()
  String projectName;
  String encodedSettings;

  final matches = IsarLinks<DbShootingMatch>;

  @ignore
  Map<String, dynamic> get jsonDecodedSettings => jsonDecode(encodedSettings);

  @ignore
  RatingProjectSettings? _settings;
  RatingProjectSettings get settings {
    if(_settings == null) {
      var jsonSettings = jsonDecodedSettings;
      var algorithmName = (jsonSettings[RatingProject.algorithmKey] ?? RatingProject.multiplayerEloValue) as String;
      var algorithm = RatingProject.algorithmForName(algorithmName, jsonSettings);
      _settings = RatingProjectSettings.decodeFromJson(algorithm, jsonSettings);
    }

    return _settings!;
  }
  set settings(RatingProjectSettings value) {
    _settings = value;
    Map<String, dynamic> map = {};
    value.encodeToJson(map);
    encodedSettings = jsonEncode(map);
  }


  final groups = IsarLinks<DbRatingGroup>();

  /// For the next full recalculation only, skip checking data entry
  /// errors.
  @ignore
  bool transientDataEntryErrorSkip;

  // Ratings
  final ratings = IsarLinks<DbShooterRating>();

  Future<List<DbShooterRating>> ratingsForGroup(DbRatingGroup group) async {
    return ratings.filter().group((q) => q.idEqualTo(group.id)).findAll();
  }

  DbRatingProject({
    required this.projectName,
    required this.sportName,
    this.encodedSettings = "{}",
    this.transientDataEntryErrorSkip = false,
  });
}

@collection
class DbRatingGroup with DbSportEntity {
  Id id = Isar.autoIncrement;

  String sportName;
  String name;

  List<String> divisionNames;
  @ignore
  List<Division> get divisions =>
      divisionNames.map((name) => sport.divisions.lookupByName(name))
      .where((result) => result != null)
      .cast<Division>()
      .toList();

  DbRatingGroup({
    required this.sportName,
    required this.name,
    this.divisionNames = const [],
  });
}

@collection
class DbShooterRating {
  Id id = Isar.autoIncrement;

  @Backlink(to: "ratings")
  final project = IsarLink<DbRatingProject>();
  final group = IsarLink<DbRatingGroup>();
}

@collection
class DbRatingEvent {
  Id id = Isar.autoIncrement;
}