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
import 'package:shooting_sports_analyst/logger.dart';

part 'ratings.g.dart';

// DbRatingProject hasMany DbRatingGroups hasMany DbShooterRatings hasMany DbRatingEvents.

var _log = SSALogger("DbRatingSchema");

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
  String name;
  String encodedSettings;

  final matches = IsarLinks<DbShootingMatch>();
  
  @ignore
  List<DbShootingMatch> transientFilteredMatches = [];

  @ignore
  Map<String, dynamic> get jsonDecodedSettings => jsonDecode(encodedSettings);

  @ignore
  RatingProjectSettings? _settings;
  @ignore
  RatingProjectSettings get settings {
    if(_settings == null) {
      var jsonSettings = jsonDecodedSettings;
      var algorithmName = (jsonSettings[RatingProject.algorithmKey] ?? RatingProject.multiplayerEloValue) as String;
      var algorithm = RatingProject.algorithmForName(algorithmName, jsonSettings);
      _settings = RatingProjectSettings.decodeFromJson(sport, algorithm, jsonSettings);
    }

    return _settings!;
  }
  set settings(RatingProjectSettings value) {
    _settings = value;
    Map<String, dynamic> map = {};
    value.encodeToJson(map);
    encodedSettings = jsonEncode(map);
  }

  final customGroups = IsarLinks<DbRatingGroup>();
  final List<String> builtinGroupNames;
  List<DbRatingGroup> get builtinRatingGroups {
    var provider = sport.builtinRatingGroupsProvider;
    if(provider == null) {
      _log.w("Attempted to get builtin rating groups for $sportName which doesn't provide them");
      return [];
    }

    return provider.builtinRatingGroups.where((e) => builtinGroupNames.contains(e.name)).toList();
  }

  @ignore
  List<DbRatingGroup> get groups {
    var list = builtinRatingGroups;
    customGroups.loadSync();
    list.addAll(customGroups);
    return list;
  }

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
    required this.name,
    required this.sportName,
    this.encodedSettings = "{}",
    this.transientDataEntryErrorSkip = false,
    this.builtinGroupNames = const [],
    RatingProjectSettings? settings,
  }) {
    if(settings != null) {
      this.settings = settings;
    }
  }
}

@collection
class DbRatingGroup with DbSportEntity {
  Id id = Isar.autoIncrement;

  @Index(composite: [CompositeIndex("name")], unique: true)
  String sportName;

  /// The long/descriptive name for this group.
  String name;

  /// The compact name for this group, suited to UI tabs or
  /// button rows.
  String? displayName;

  @ignore
  String get uiLabel => displayName ?? name;

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
    this.displayName,
    this.divisionNames = const [],
  });
}

@collection
class DbShooterRating {
  Id id = Isar.autoIncrement;

  @Index(composite: [CompositeIndex("group")], unique: true)
  @Backlink(to: "ratings")
  final project = IsarLink<DbRatingProject>();
  final group = IsarLink<DbRatingGroup>();
}

@collection
class DbRatingEvent {
  Id id = Isar.autoIncrement;
}