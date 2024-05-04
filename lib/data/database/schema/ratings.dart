/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:convert';

import 'package:isar/isar.dart';
import 'package:shooting_sports_analyst/data/database/schema/match.dart';
import 'package:shooting_sports_analyst/data/ranking/interface/rating_data_source.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_change.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_system.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/project_manager.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/registry.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/shooter.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/filter_dialog.dart';
import 'package:shooting_sports_analyst/util.dart';
import 'package:uuid/v1.dart';
import 'package:uuid/v4.dart';

part 'ratings.g.dart';

// DbRatingProject hasMany DbRatingGroups hasMany DbShooterRatings hasMany DbRatingEvents.

var _log = SSALogger("DbRatingSchema");

mixin DbSportEntity {
  String get sportName;

  @ignore
  Sport get sport => SportRegistry().lookup(sportName)!;
}

@collection
class DbRatingProject with DbSportEntity implements RatingDataSource, EditableRatingDataSource {
  Id id = Isar.autoIncrement;

  @Index()
  String sportName;

  // Settings
  @Index()
  String name;
  String encodedSettings;

  /// All of the matches this project includes.
  ///
  /// See also [filteredMatches] and [lastUsedMatches].
  final matches = IsarLinks<DbShootingMatch>();

  /// A subset of the matches from this project, which will actually be used to calculate
  /// the ratings.
  ///
  /// This allows e.g. the configure-ratings screen filters to generate ratings for a subset
  /// of the overall list of matches in a project.
  final filteredMatches = IsarLinks<DbShootingMatch>();

  /// The IsarLinks of matches to use for calculating ratings for this project. If
  /// [filteredMatches] is not empty, it will be used. If it is empty, [matches] will
  /// be used instead.
  ///
  /// If [loadLinks] is true, the returned IsarLinks will be loaded.
  Future<IsarLinks<DbShootingMatch>> matchesToUse({bool loadLinks = true}) async {
    var filteredCount = await filteredMatches.count();

    if(filteredCount == 0) {
      if(loadLinks && !matches.isLoaded) {
        await matches.load();
      }
      return matches;
    }
    else {
      if(loadLinks && !filteredMatches.isLoaded) {
        await filteredMatches.load();
      }

      return filteredMatches;
    }
  }

  /// The set of matches last used to calculate ratings for this match.
  ///
  /// When this differs from [matchesToUse], match addition or recalculation
  /// is required.
  final lastUsedMatches = IsarLinks<DbShootingMatch>();

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

  final dbGroups = IsarLinks<DbRatingGroup>();

  @ignore
  List<DbRatingGroup> get groups {
    if(!dbGroups.isLoaded) {
      dbGroups.loadSync();
    }
    return []..addAll(dbGroups);
  }

  /// For the next full recalculation only, skip checking data entry
  /// errors.
  @ignore
  bool transientDataEntryErrorSkip;

  /// Delete all shooter ratings and rating events belonging to this project.
  Future<void> resetRatings() async {
    await ratings.load();
    var eventCount = 0;
    ratings.forEach((r) {
      // TODO: r.resetEvents
    });

    var count = await ratings.filter().deleteAll();
    _log.i("Cleared $count ratings and $eventCount events");
  }

  // Ratings
  final ratings = IsarLinks<DbShooterRating>();

  Future<List<DbShooterRating>> ratingsForGroup(DbRatingGroup group) async {
    return ratings.filter().group((q) => q.uuidEqualTo(group.uuid)).findAll();
  }

  DbRatingProject({
    required this.name,
    required this.sportName,
    this.encodedSettings = "{}",
    this.transientDataEntryErrorSkip = false,
    RatingProjectSettings? settings,
  }) {
    if(settings != null) {
      this.settings = settings;
    }
  }

  @override
  Future<DataSourceResult<List<int>>> getMatchDatabaseIds() async {
    if(!matches.isLoaded) {
      await matches.load();
    }

    return DataSourceResult.ok(matches.map((m) => m.id).toList());
  }

  @override
  Future<DataSourceResult<RatingProjectSettings>> getSettings() {
    return Future.value(DataSourceResult.ok(settings));
  }

  @override
  Future<DataSourceResult<List<String>>> matchSourceIds() async {
    if(!matches.isLoaded) {
      await matches.load();
    }

    return DataSourceResult.ok(matches.map((m) => m.sourceIds.first).toList());
  }

  @override
  Future<DataSourceResult<List<DbRatingGroup>>> getGroups() {
    return Future.value(DataSourceResult.ok(groups));
  }
}

@collection
class DbRatingGroup with DbSportEntity {
  Id get id => uuid.stableHash;

  @Index(unique: true)
  String uuid;

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

  @ignore
  FilterSet get filters {
    var f = FilterSet(
      sport,
      empty: true,
    );

    f.mode = FilterMode.or;
    f.reentries = false;
    f.scoreDQs = false;

    f.divisions = FilterSet.divisionListToMap(divisions);

    return f;
  }

  /// Default constructor for Isar.
  DbRatingGroup({
    required this.uuid,
    required this.sportName,
    required this.name,
    this.displayName,
    this.divisionNames = const [],
  });

  /// Constructor that will create a new UUID if a string ID is not provided.
  DbRatingGroup.create({
    String? uuid,
    required this.sportName,
    required this.name,
    this.displayName,
    this.divisionNames = const [],
  }) : this.uuid = uuid ?? UuidV4().generate() ;
}

/// DbSportRating is the database embodiment of shooter ratings. It should almost always
/// be wrapped by one of the subclasses of ShooterRating, which will wrap the various generic
/// data variables on this class.
@collection
class DbShooterRating extends Shooter with DbSportEntity {
  String sportName;

  Id id = Isar.autoIncrement;

  @ignore
  bool get isPersisted => id != Isar.autoIncrement;

  @Index(type: IndexType.hashElements)
  List<String> get dbKnownMemberNumbers => List<String>.from(knownMemberNumbers);

  @Index()
  List<String> get firstNameParts => firstName.split(RegExp(r'\w+'));
  @Index()
  List<String> get lastNameParts => lastName.split(RegExp(r'\w+'));

  @Index()
  String get deduplicatorName {
    var processedFirstName = firstName.toLowerCase().replaceAll(RegExp(r"\s+"), "");
    var processedLastName = lastName.toLowerCase().replaceAll(RegExp(r"\s+"), "");

    return "$processedFirstName$processedLastName";
  }

  String? ageCategoryName;

  @Index(composite: [CompositeIndex("group")], unique: true)
  @Backlink(to: "ratings")
  final project = IsarLink<DbRatingProject>();
  final group = IsarLink<DbRatingGroup>();
  final events = IsarLinks<DbRatingEvent>();

  int get length => events.countSync();

  double rating;
  double error;
  double connectedness;

  /// Use to store algorithm-specific double data.
  List<double> doubleData = [];
  /// Use to store algorithm-specific integer data.
  List<int> intData = [];
  
  DbShooterRating({
    required this.sportName,
    required super.firstName,
    required super.lastName,
    required super.memberNumber,
    required super.female,
    required this.rating,
    required this.error,
    required this.connectedness,
  });

}

@collection
class DbRatingEvent {
  Id id = Isar.autoIncrement;
}