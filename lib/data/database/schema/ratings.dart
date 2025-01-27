/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:isar/isar.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/match.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/connectivity.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/rating_report.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/interface/rating_data_source.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_change.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_system.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/legacy_loader/project_manager.dart';
import 'package:shooting_sports_analyst/data/ranking/project_settings.dart';
import 'package:shooting_sports_analyst/data/source/registered_sources.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/registry.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/scoring.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/filter_dialog.dart';
import 'package:shooting_sports_analyst/util.dart';
import 'package:uuid/v4.dart';

export 'package:shooting_sports_analyst/data/database/schema/ratings/shooter_rating.dart' show DbShooterRating;

part 'ratings.g.dart';

// DbRatingProject hasMany DbRatingGroups hasMany DbShooterRatings hasMany DbRatingEvents.

var _log = SSALogger("DbRatingSchema");

/// A mixin that provides a convenience property [sport] to access the sport
/// associated with this entity, stored in [sportName]. To use, mix in this
/// class and add a [sportName] property to the class.
mixin DbSportEntity {
  /// Do not set sportName directly. Instead, use [sport].
  String get sportName;
  /// Do not set sportName directly. Instead, use [sport].
  set sportName(String value);

  /// The sport associated with this entity.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @ignore
  Sport get sport => SportRegistry().lookup(sportName)!;
  set sport(Sport s) => sportName = s.name;
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
  /// See also [filteredMatchPointers] and [lastUsedMatches].
  List<MatchPointer> matchPointers = [];

  /// Retained for compatibility with old projects. Do not use.
  final IsarLinks<DbShootingMatch> matches = IsarLinks();

  /// A subset of the matches from this project, which will actually be used to calculate
  /// the ratings.
  ///
  /// This allows e.g. the configure-ratings screen filters to generate ratings for a subset
  /// of the overall list of matches in a project.
  List<MatchPointer> filteredMatchPointers = [];

  /// Retained for compatibility with old projects. Do not use.
  final IsarLinks<DbShootingMatch> filteredMatches = IsarLinks();

  /// A list of ongoing matches, which may be treated slightly differently by the rating
  /// algorithm.
  List<MatchPointer> matchInProgressPointers = [];

  /// Retained for compatibility with old projects. Do not use.
  final IsarLinks<DbShootingMatch> matchesInProgress = IsarLinks();
  /// True if a full calculation has been completed for this project (set by the project
  /// loader). A project with this flag set to false cannot have matches appended, and
  /// must complete a full calculation before it can be used.
  bool completedFullCalculation = false;

  /// The IsarLinks of matches to use for calculating ratings for this project. If
  /// [filteredMatchPointers] is not empty, it will be used. If it is empty, [matchPointers] will
  /// be used instead.
  ///
  /// If [loadLinks] is true, the returned IsarLinks will be loaded.
  List<MatchPointer> matchesToUse() {
    var filteredCount = filteredMatchPointers.length;

    if(filteredCount == 0) {
      return matchPointers;
    }
    else {
      return filteredMatchPointers;
    }
  }

  /// Links to all of the ratings in this project.
  final ratings = IsarLinks<DbShooterRating>();

  /// A list of reports generated since the last full recalculation.
  List<RatingReport> reports = [];

  Future<void> resetMatches() async {
    // TODO
  }

  @ignore
  ConnectivityContainer connectivityContainer = ConnectivityContainer();

  List<BaselineConnectivity> get dbBaselineConnectivities => connectivityContainer.toList();
  set dbBaselineConnectivities(List<BaselineConnectivity> value) => connectivityContainer.addAll(value);

  /// The set of matches last used to calculate ratings for this match.
  ///
  /// When this differs from [matchesToUse], match addition or recalculation
  /// is required.
  final List<MatchPointer> lastUsedMatches = [];

  @ignore
  Map<String, dynamic> get jsonDecodedSettings => jsonDecode(encodedSettings);

  @ignore
  RatingProjectSettings? _settings;
  @ignore
  RatingProjectSettings get settings {
    if(_settings == null) {
      var jsonSettings = jsonDecodedSettings;
      var algorithmName = (jsonSettings[OldRatingProject.algorithmKey] ?? OldRatingProject.multiplayerEloValue) as String;
      var algorithm = RatingSystem.algorithmForName(algorithmName, jsonSettings);
      _settings = RatingProjectSettings.decodeFromJson(sport, algorithm, jsonSettings);
    }

    return _settings!;
  }
  /// Set the settings for this project. This will also update [encodedSettings]
  /// so that changes are persisted to the database on the next save.
  set settings(RatingProjectSettings value) {
    _settings = value;
    Map<String, dynamic> map = {};
    value.encodeToJson(map);
    encodedSettings = jsonEncode(map);
  }

  /// Call after changing the map returned by [settings]. This updates [encodedSettings]
  /// so that changes are persisted to the database on the next save.
  void changedSettings() {
    if(_settings != null) {
      Map<String, dynamic> map = {};
      _settings!.encodeToJson(map);
      encodedSettings = jsonEncode(map);
    }
    else {
      throw StateError("Settings not yet loaded");
    }
  }

  final dbGroups = IsarLinks<RatingGroup>();

  /// A list of member number mappings detected automatically while loading this
  /// project.
  List<DbMemberNumberMapping> automaticNumberMappings = [];

  /// Look up an automatic member number mapping for a given source number.
  ///
  /// Returns null if no mapping is found.
  DbMemberNumberMapping? lookupAutomaticNumberMapping(String sourceNumber) {
    if(_automaticNumberMappingCache == null) {
      _automaticNumberMappingCache = {};
      for(var mapping in automaticNumberMappings) {
        for(var sourceNumber in mapping.sourceNumbers) {
          _automaticNumberMappingCache![sourceNumber] = mapping;
        }
      }
    }

    return _automaticNumberMappingCache![sourceNumber];
  }

  /// Look up an automatic number mapping by its target number.
  /// 
  /// Uncached; use with care.
  DbMemberNumberMapping? lookupAutomaticNumberMappingByTarget(String targetNumber) {
    return automaticNumberMappings.firstWhereOrNull((mapping) => mapping.targetNumber == targetNumber);
  }

  /// Clear the automatic number mapping cache.
  void clearAutomaticNumberMappingCache() {
    _automaticNumberMappingCache = null;
  }

  @ignore
  Map<String, DbMemberNumberMapping>? _automaticNumberMappingCache;

  @ignore
  List<RatingGroup> get groups {
    if(!dbGroups.isLoaded) {
      dbGroups.loadSync();
    }
    return []..addAll(dbGroups.sorted((a, b) => a.sortOrder.compareTo(b.sortOrder)));
  }
  set groups(List<RatingGroup> value) {
    dbGroups.clear();
    dbGroups.addAll(value.sorted((a, b) => a.sortOrder.compareTo(b.sortOrder)));
  }

  /// For the next full recalculation only, skip checking data entry
  /// errors.
  @ignore
  bool transientDataEntryErrorSkip;

  /// Delete all shooter ratings and rating events belonging to this project.
  Future<void> resetRatings() async {
    return AnalystDatabase().isar.writeTxn(() async {
      await ratings.load();
      var eventCount = 0;
      for(var r in ratings) {
        var count = await r.events.filter().deleteAll();
        await r.events.reset();
        eventCount += count;
      }

      lastUsedMatches.clear();
      var count = await ratings.filter().deleteAll();
      await ratings.reset();
      _log.i("Cleared $count ratings and $eventCount events");
    });
  }

  // TODO: we can make these more efficient by querying the Ratings collection
  // (since we can probably composite-index that by interesting queries)
  Future<DataSourceResult<List<DbShooterRating>>> getRatings(RatingGroup group) async {
    return DataSourceResult.ok(await ratings.filter().group((q) => q.idEqualTo(group.id)).findAll());
  }

  Future<DataSourceResult<List<DbShooterRating>>> getRatingsByDeduplicatorName(RatingGroup group, String deduplicatorName) async {
    return DataSourceResult.ok(await ratings.filter()
      .group((q) => q.idEqualTo(group.id))
      .deduplicatorNameEqualTo(deduplicatorName)
      .findAll());
  }

  DbRatingProject({
    required this.name,
    required this.sportName,
    this.encodedSettings = "{}",
    this.transientDataEntryErrorSkip = false,
    this.automaticNumberMappings = const [],
    RatingProjectSettings? settings,
  }) {
    if(settings != null) {
      this.settings = settings;
    }
  }

  @override
  Future<DataSourceResult<List<int>>> getMatchDatabaseIds() async {
    return DataSourceResult.ok(matchPointers.map((m) => m.localDbId).whereNotNull().toList());
  }

  @override
  Future<DataSourceResult<Sport>> getSport() async {
    return DataSourceResult.ok(sport);
  }

  @override
  Future<DataSourceResult<RatingProjectSettings>> getSettings() {
    return Future.value(DataSourceResult.ok(settings));
  }

  @override
  Future<DataSourceResult<List<String>>> getMatchSourceIds() async {
    return DataSourceResult.ok(matchPointers.map((m) => m.sourceIds.first).toList());
  }

  @override
  Future<DataSourceResult<DbShootingMatch>> getLatestMatch() async {
    var match = matchPointers.sorted((a, b) => b.date!.compareTo(a.date!)).firstOrNull;
    if(match == null) {
      return DataSourceResult.err(DataSourceError.invalidRequest);
    }
    else {
      return match.getDbMatch(AnalystDatabase());
    }
  }

  @override
  Future<DataSourceResult<List<RatingGroup>>> getGroups() {
    return Future.value(DataSourceResult.ok(groups));
  }

  @override
  Future<DataSourceResult<RatingGroup?>> groupForDivision(Division? division) {
    var fewestDivisions = 65536;
    RatingGroup? outGroup = null;
    if(division == null) {
      // TODO: this might not be the right result for a null division
      return Future.value(DataSourceResult.ok(groups.firstOrNull));
    }

    for(var group in groups) {
      if(group.divisions.length < fewestDivisions && group.divisions.contains(division)) {
        fewestDivisions = group.divisions.length;
        outGroup = group;
      }
    }

    return Future.value(DataSourceResult.ok(outGroup));
  }


  @override
  Future<DataSourceResult<DbShooterRating?>> lookupRating(RatingGroup group, String memberNumber, {bool allPossibleMemberNumbers = false}) async {
    List<DbShooterRating> results = [];
    if(allPossibleMemberNumbers) {
      results = await ratings
        .filter()
        .dbAllPossibleMemberNumbersElementMatches(memberNumber)
        .and()
        .group((q) => q.idEqualTo(group.id))
        .findAll();
    }
    else {
      results = await ratings
        .filter()
        .dbKnownMemberNumbersElementMatches(memberNumber)
        .and()
        .group((q) => q.idEqualTo(group.id))
        .findAll();
    }
    return DataSourceResult.ok(results.firstOrNull);
  }

  @override
  Future<DataSourceResult<String>> getProjectName() {
    return Future.value(DataSourceResult.ok(name));
  }

  @override
  Future<DataSourceResult<ShooterRating>> wrapDbRating(DbShooterRating rating) {
    return Future.value(DataSourceResult.ok(settings.algorithm.wrapDbRating(rating)));
  }
}

@embedded
class DbMemberNumberMapping {
  String deduplicatorName;
  List<String> sourceNumbers;
  String targetNumber;
  bool automatic;

  DbMemberNumberMapping({
    this.deduplicatorName = "",
    this.sourceNumbers = const [],
    this.targetNumber = "",
    this.automatic = false,
  });

  operator ==(Object other) {
    if(!(other is DbMemberNumberMapping)) return false;
    if(other.sourceNumbers.length != sourceNumbers.length) return false;
    if(other.targetNumber != targetNumber) return false;
    if(other.deduplicatorName != deduplicatorName) return false;
    if(other.automatic != automatic) return false;
    if(!other.sourceNumbers.containsAll(sourceNumbers)) return false;
    return true;
  }

  int get hashCode =>
    Object.hash(deduplicatorName, targetNumber, automatic, Object.hashAllUnordered(sourceNumbers));
}

/// A RatingGroup is a collection of competitors rated against one another.
///
/// [uuid] is a unique identifier for the group. For hardcoded rating
/// groups, specify an ID of the form 'sportName-groupName'.
@collection
class RatingGroup with DbSportEntity {
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

  int sortOrder;

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

    f.divisions = FilterSet.divisionListToMap(sport, divisions);

    return f;
  }

  /// Default constructor for Isar.
  RatingGroup({
    required this.uuid,
    required this.sportName,
    required this.name,
    this.sortOrder = 0,
    this.displayName,
    this.divisionNames = const [],
  });

  /// Constructor that will create a new UUID if a string ID is not provided.
  RatingGroup.create({
    String? uuid,
    required this.sportName,
    required this.name,
    this.sortOrder = 0,
    this.displayName,
    this.divisionNames = const [],
  }) : this.uuid = uuid ?? UuidV4().generate();

  @override
  String toString() {
    return name;
  }

  @override
  int get hashCode => Object.hash(uuid, sportName);

  @override
  operator ==(Object other) {
    if(!(other is RatingGroup)) return false;
    return other.uuid == uuid && other.sportName == sportName;
  }
}

/// MatchPointer is a database record containing enough information
/// to locate a match in the database, display in the UI, and sort
/// by relevant fields like level, date, and sport.
/// 
/// [DbShootingMatch] is a heavyweight object, so we want to avoid
/// using IsarLinks to it for the configure screen (it takes a long
/// time to load).
@embedded
@JsonSerializable()
class MatchPointer with DbSportEntity implements SourceIdsProvider {
  String sportName;

  String name;

  /// Should never actually be null, but Isar can't handle
  /// required fields that don't have const constructors.
  DateTime? date;
  /// The match source code for the source that originally downloaded this match.
  String sourceCode;
  /// Source IDs known by the source described by [sourceCode] for this match.
  List<String> sourceIds;
  /// The name of the match level for this match.
  String? matchLevelName;
  /// The match level for this match, looked up from [matchLevelName].
  @ignore
  MatchLevel? get level => sport.eventLevels.lookupByName(matchLevelName);
  /// The database ID of this match in the local database.
  @JsonKey(includeFromJson: false, includeToJson: false)
  int? localDbId;

  MatchPointer({
    this.sportName = "invalid",
    this.name = "(unknown)",
    this.date,
    this.sourceCode = "",
    this.sourceIds = const [],
    this.matchLevelName,
    this.localDbId,
  });

  MatchPointer.fromMatch(ShootingMatch match) :
    sportName = match.sport.name,
    name = match.name,
    date = match.date,
    sourceCode = match.sourceCode,
    sourceIds = match.sourceIds,
    matchLevelName = match.level?.name,
    localDbId = match.databaseId;

  MatchPointer.fromDbMatch(DbShootingMatch match) :
    sportName = match.sportName,
    name = match.eventName,
    date = match.date,
    sourceCode = match.sourceCode,
    sourceIds = match.sourceIds,
    localDbId = match.id 
  {
    matchLevelName = match.matchLevelName;
  }

  /// Get the [DbShootingMatch] associated with this [MatchPointer].
  ///
  /// Returns [DataSourceError.invalidRequest] if [localDbId] is null or
  /// [sourceCode] is not a valid source code and a download was requested.
  /// Returns [DataSourceError.notFound] if the match is not found in the database,
  /// or if [downloadIfMissing] is true and the match cannot be downloaded.
  Future<DataSourceResult<DbShootingMatch>> getDbMatch(AnalystDatabase db, {bool downloadIfMissing = false}) async {
    if(localDbId == null) {
      return DataSourceResult.err(DataSourceError.invalidRequest);
    }
    var match = await db.getMatch(localDbId!);
    if(match == null) {
      if(downloadIfMissing) {
        var source = MatchSourceRegistry().getByCodeOrNull(sourceCode);
        if(source == null || !source.supportedSports.contains(sport.type)) {
          return DataSourceResult.err(DataSourceError.invalidRequest);
        }
        
        var result = await source.getMatchFromId(sourceIds.first, sport: sport);
        
        if(result.isErr()) {
          return DataSourceResult.err(DataSourceError.database);
        }
        var dbMatch = await db.saveMatch(result.unwrap());
        if(dbMatch.isErr()) {
          return DataSourceResult.err(DataSourceError.database);
        }
        return DataSourceResult.ok(dbMatch.unwrap());
      }
      else {
        return DataSourceResult.err(DataSourceError.notFound);
      }
    }
    return DataSourceResult.ok(match);
  }

  DbShootingMatch intoSourcePlaceholder() {
    return DbShootingMatch.sourcePlaceholder(
      sport: sport,
      sourceCode: sourceCode,
      sourceIds: sourceIds,
    );
  }

  factory MatchPointer.fromJson(Map<String, dynamic> json) => _$MatchPointerFromJson(json);
  Map<String, dynamic> toJson() => _$MatchPointerToJson(this);

  /// Two [MatchPointer]s are considered equal if they have the same [sourceCode]
  /// and the same set of [sourceIds].
  @override
  operator ==(Object other) {
    if(!(other is MatchPointer)) return false;

    if(other.sourceCode != sourceCode) return false;
    if(sourceIds.length != other.sourceIds.length) return false;
    if(sourceIds.intersection(other.sourceIds).length != sourceIds.length) return false;
    return true;
  }

  @override
  int get hashCode => Object.hash(sourceCode, Object.hashAllUnordered(sourceIds));
}
