/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:isar/isar.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:shooting_sports_analyst/closed_sources/psv2/psv2_source.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/match.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/connectivity.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/rating_report.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/interface/rating_data_source.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_system.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/legacy_loader/project_manager.dart';
import 'package:shooting_sports_analyst/data/ranking/project_settings.dart';
import 'package:shooting_sports_analyst/data/source/registered_sources.dart';
import 'package:shooting_sports_analyst/data/source/source.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/registry.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
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

mixin DbDivisionEntity on DbSportEntity {
  String get divisionName;
  set divisionName(String value);

  @JsonKey(includeFromJson: false, includeToJson: false)
  @ignore
  Division? get division => sport.divisions.lookupByName(divisionName);
  set division(Division? d) => divisionName = d?.name ?? "";
}

@collection
class DbRatingProject with DbSportEntity implements RatingDataSource, EditableRatingDataSource {
  Id id = Isar.autoIncrement;

  @override
  Future<DataSourceResult<int>> getProjectId() async {
    return DataSourceResult.ok(id);
  }

  @Index()
  String sportName;

  // Settings
  @Index()
  String name;
  String encodedSettings;

  /// An internal field for storing [created].
  @Index()
  DateTime? dbCreated;
  /// When this project was created.
  DateTime get created => dbCreated ?? DateTime(2025, 4, 1);
  set created(DateTime value) {
    dbCreated = value;
  }

  /// An internal field for storing [updated].
  @Index()
  DateTime? dbUpdated;
  /// When this project was last updated (i.e., when a calculation was last performed).
  DateTime get updated => dbUpdated ?? DateTime(2025, 4, 1);
  set updated(DateTime value) {
    dbUpdated = value;
  }

  /// An internal field for storing [loaded].
  @Index()
  DateTime? dbLoaded;
  /// When this project was last loaded (i.e., when it was viewed in the main rating list).
  DateTime get loaded => dbLoaded ?? DateTime(2025, 4, 1);
  set loaded(DateTime value) {
    dbLoaded = value;
  }

  /// All of the matches this project includes.
  ///
  /// See also [filteredMatchPointers] and [lastUsedMatches].
  List<MatchPointer> matchPointers = [];

  /// A subset of the matches from this project, which will actually be used to calculate
  /// the ratings.
  ///
  /// This allows e.g. the configure-ratings screen filters to generate ratings for a subset
  /// of the overall list of matches in a project.
  List<MatchPointer> filteredMatchPointers = [];

  /// A list of ongoing matches, which may be treated slightly differently by the rating
  /// algorithm.
  List<MatchPointer> matchInProgressPointers = [];

  /// True if a full calculation has been completed for this project (set by the project
  /// loader). A project with this flag set to false cannot have matches appended, and
  /// must complete a full calculation before it can be used.
  bool completedFullCalculation = false;

  /// The list of matches to use for calculating ratings for this project. If
  /// [filteredMatchPointers] is not empty, it will be used. If it is empty, [matchPointers] will
  /// be used instead.
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
  Future<DataSourceResult<List<RatingReport>>> getAllReports() {
    return Future.value(DataSourceResult.ok(reports));
  }

  /// A list of reports generated during the last calculation, full or not.
  List<RatingReport> recentReports = [];
  Future<DataSourceResult<List<RatingReport>>> getRecentReports() {
    return Future.value(DataSourceResult.ok(recentReports));
  }

  void addReport(RatingReport report) {
    var dup = false;
    if(!recentReports.contains(report)) {
      recentReports.add(report);
    }
    else {
      dup = true;
    }
    if(!reports.contains(report)) {
      reports.add(report);
    }

    if(dup) {
      _log.i("Duplicate report: ${report.toString()}");
    }
    else {
      _log.i("Added report: ${report.toString()}");
    }
  }

  /// The number of rating events in this project.
  int eventCount = 0;

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
  List<MatchPointer> lastUsedMatches = [];

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
  set groups(Iterable<RatingGroup> value) {
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

      lastUsedMatches = [];
      var count = await ratings.filter().deleteAll();
      await ratings.reset();
      _log.i("Cleared $count ratings and $eventCount events");
    });
  }

  DbRatingProject({
    required this.name,
    required this.sportName,
    this.encodedSettings = "{}",
    this.transientDataEntryErrorSkip = false,
    this.automaticNumberMappings = const [],
    this.dbCreated,
    this.dbUpdated,
    this.dbLoaded,
    RatingProjectSettings? settings,
  }) {
    if(settings != null) {
      this.settings = settings;
    }
  }

  // TODO: we can make these more efficient by querying the Ratings collection
  // (since we can probably composite-index that by interesting queries)
  @override
  Future<DataSourceResult<List<DbShooterRating>>> getRatings(RatingGroup group) async {
    return DataSourceResult.ok(await ratings.filter()
      .group((q) => q.idEqualTo(group.id))
      .findAll());
  }

  Future<DataSourceResult<List<DbShooterRating>>> getRatingsByDeduplicatorName(RatingGroup group, String deduplicatorName) async {
    return DataSourceResult.ok(await ratings.filter()
      .group((q) => q.idEqualTo(group.id))
      .deduplicatorNameEqualTo(deduplicatorName)
      .findAll());
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
  Future<DataSourceResult<List<MatchPointer>>> getMatchPointers() async {
    return DataSourceResult.ok(matchPointers);
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

  Map<String, dynamic> toJson() {
    Map<String, dynamic> json = {};
    json["name"] = name;
    json["sportName"] = sportName;
    json["encodedSettings"] = encodedSettings;
    json["automaticNumberMappings"] = automaticNumberMappings.map((m) => m.toJson()).toList();
    json["builtinGroups"] = groups.where((g) => g.builtin).map((g) => g.uuid).toList();
    json["customGroups"] = groups.where((g) => !g.builtin).map((g) => g.toJson()).toList();
    json["matchPointers"] = matchPointers.map((m) => m.toJson()).toList();
    json["filteredMatchPointers"] = filteredMatchPointers.map((m) => m.toJson()).toList();
    json["matchInProgressPointers"] = matchInProgressPointers.map((m) => m.toJson()).toList();
    return json;
  }

  factory DbRatingProject.fromJson(Map<String, dynamic> json) {
    var sport = SportRegistry().lookup(json["sportName"]);
    if(sport == null) {
      throw ArgumentError("Invalid sport name: ${json["sportName"]}");
    }
    var project = DbRatingProject(
      name: json["name"] as String,
      sportName: json["sportName"] as String,
      encodedSettings: json["encodedSettings"] as String,
      automaticNumberMappings: (json["automaticNumberMappings"] as List<dynamic>).map((m) => DbMemberNumberMapping.fromJson(m as Map<String, dynamic>)).cast<DbMemberNumberMapping>().toList(),
    );
    var builtinGroups = (json["builtinGroups"] as List<dynamic>).map((uuid) => sport.builtinRatingGroupsProvider?.getGroup(uuid as String));
    var customGroups = (json["customGroups"] as List<dynamic>).map((g) => RatingGroup.fromJson(g as Map<String, dynamic>));

    for(var group in customGroups) {
      var isar = AnalystDatabase().isar;
      isar.writeTxnSync(() {
        isar.ratingGroups.putSync(group);
      });
    }

    project.groups = [...builtinGroups.whereNotNull(), ...customGroups];

    project.matchPointers = (json["matchPointers"] as List<dynamic>).map((m) => MatchPointer.fromJson(m as Map<String, dynamic>)).toList();
    project.filteredMatchPointers = (json["filteredMatchPointers"] as List<dynamic>).map((m) => MatchPointer.fromJson(m as Map<String, dynamic>)).toList();
    project.matchInProgressPointers = (json["matchInProgressPointers"] as List<dynamic>).map((m) => MatchPointer.fromJson(m as Map<String, dynamic>)).toList();
    return project;
  }
}

@embedded
@JsonSerializable()
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

  Map<String, dynamic> toJson() => _$DbMemberNumberMappingToJson(this);
  factory DbMemberNumberMapping.fromJson(Map<String, dynamic> json) => _$DbMemberNumberMappingFromJson(json);

  DbMemberNumberMapping copy() {
    return DbMemberNumberMapping(
      deduplicatorName: deduplicatorName,
      sourceNumbers: sourceNumbers.toList(),
      targetNumber: targetNumber,
      automatic: automatic,
    );
  }
}

/// A RatingGroup is a collection of competitors rated against one another.
///
/// [uuid] is a unique identifier for the group. For hardcoded rating
/// groups, specify an ID of the form 'sportName-groupName'.
@collection
@JsonSerializable()
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

  bool builtin;

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
    this.builtin = false,
  });

  /// Constructor for a built-in rating group that will create a new UUID
  /// if a string ID is not provided.
  RatingGroup.newBuiltIn({
    String? uuid,
    required this.sportName,
    required this.name,
    this.sortOrder = 0,
    this.displayName,
    required this.divisionNames,
  }) : this.builtin = true, this.uuid = uuid ?? UuidV4().generate();

  /// Constructor for a custom rating group that will create a new UUID
  /// if a string ID is not provided.
  RatingGroup.newCustom({
    String? uuid,
    required this.sportName,
    required this.name,
    this.sortOrder = 0,
    this.displayName,
    this.divisionNames = const [],
  }) : this.builtin = false, this.uuid = uuid ?? UuidV4().generate();

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

  Map<String, dynamic> toJson() => _$RatingGroupToJson(this);
  factory RatingGroup.fromJson(Map<String, dynamic> json) => _$RatingGroupFromJson(json);
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
  Future<DataSourceResult<DbShootingMatch>> getDbMatch(AnalystDatabase db, {bool downloadIfMissing = false, bool ignoreUnknownDivisions = false}) async {
    DbShootingMatch? match;
    if(localDbId != null) {
      match = await db.getMatch(localDbId!);
      if(match != null) {
        return DataSourceResult.ok(match);
      }
    }
    if(match == null) {
      match = await db.getMatchByAnySourceId(sourceIds);
      if(match != null) {
        return DataSourceResult.ok(match);
      }
      else if(downloadIfMissing) {
        var source = MatchSourceRegistry().getByCodeOrNull(sourceCode);
        if(source == null || !source.supportedSports.contains(sport.type)) {
          _log.e("Unable to download missing match: source $sourceCode source supported sports${source?.supportedSports} match sport type ${sport.type}");
          return DataSourceResult.err(DataSourceError.invalidRequest);
        }

        InternalMatchFetchOptions? options;
        if(source is PSv2MatchSource) {
          options = PSv2MatchFetchOptions(
            ignoreUnknownDivisions: ignoreUnknownDivisions,
          );
        }

        var result = await source.getMatchFromId(sourceIds.first, sport: sport, options: options);

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
    return DataSourceResult.err(DataSourceError.notFound);
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
