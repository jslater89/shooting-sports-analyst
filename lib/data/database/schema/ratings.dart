/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:isar/isar.dart';
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
  /// See also [filteredMatches] and [lastUsedMatches].
  final matches = IsarLinks<DbShootingMatch>();

  /// A subset of the matches from this project, which will actually be used to calculate
  /// the ratings.
  ///
  /// This allows e.g. the configure-ratings screen filters to generate ratings for a subset
  /// of the overall list of matches in a project.
  final filteredMatches = IsarLinks<DbShootingMatch>();

  /// A list of ongoing matches, which may be treated slightly differently by the rating
  /// algorithm.
  final matchesInProgress = IsarLinks<DbShootingMatch>();

  /// True if a full calculation has been completed for this project (set by the project
  /// loader). A project with this flag set to false cannot have matches appended, and
  /// must complete a full calculation before it can be used.
  bool completedFullCalculation = false;

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
  final lastUsedMatches = IsarLinks<DbShootingMatch>();

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
    return []..addAll(dbGroups);
  }
  set groups(List<RatingGroup> value) {
    dbGroups.clear();
    dbGroups.addAll(value);
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

      await lastUsedMatches.reset();
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
    if(!matches.isLoaded) {
      await matches.load();
    }

    return DataSourceResult.ok(matches.map((m) => m.id).toList());
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
    if(!matches.isLoaded) {
      await matches.load();
    }

    return DataSourceResult.ok(matches.map((m) => m.sourceIds.first).toList());
  }

  @override
  Future<DataSourceResult<DbShootingMatch>> getLatestMatch() async {
    var match = await matches.filter().sortByDateDesc().findFirst();
    if(match == null) {
      return DataSourceResult.err(DataSourceError.invalidRequest);
    }
    else {
      return DataSourceResult.ok(match);
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
  Future<DataSourceResult<DbShooterRating?>> lookupRating(RatingGroup group, String memberNumber) async {
    var results = await ratings
        .filter()
        .dbKnownMemberNumbersElementMatches(memberNumber)
        .and()
        .group((q) => q.idEqualTo(group.id)).findAll();

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
    this.displayName,
    this.divisionNames = const [],
  });

  /// Constructor that will create a new UUID if a string ID is not provided.
  RatingGroup.create({
    String? uuid,
    required this.sportName,
    required this.name,
    this.displayName,
    this.divisionNames = const [],
  }) : this.uuid = uuid ?? UuidV4().generate();

  @override
  String toString() {
    return name;
  }
}

@collection
class DbRatingEvent implements IRatingEvent {
  Id id = Isar.autoIncrement;

  @ignore
  bool get isPersisted => id != Isar.autoIncrement;

  @Backlink(to: 'events')
  final owner = IsarLink<DbShooterRating>();

  /// The match. See [setMatch].
  final match = IsarLink<DbShootingMatch>();

  Future<void> setMatchId(String id, {bool load = false}) {
    matchId = id;
    if(load) {
      return match.load();
    }
    else {
      return Future.value();
    }
  }
  
  /// Set the match for this event, updating both the [match] link
  /// and [matchId].
  Future<void> setMatch(DbShootingMatch m, {bool save = true}) {
    matchId = m.sourceIds.first;
    match.value = m;
    if(save) {
      return match.save();
    }
    else {
      return Future.value();
    }
  }

  /// A match identifier for the match. See [setMatch].
  String matchId;

  /// The shooter's entry number in this match.
  int entryId;

  /// The stage number of this score, or -1 if this is a rating event
  /// for a full match or a match without stages.
  int stageNumber;

  DateTime date;
  double ratingChange;
  double oldRating;
  @ignore
  double get newRating => oldRating + ratingChange;

  /// A synthetic incrementing value used to sort rating events by date and stage
  /// number.
  @Index()
  int get dateAndStageNumber => (date.millisecondsSinceEpoch ~/ 1000) + stageNumber;

  /// Floating-point data used by specific kinds of rating events.
  List<double> doubleData;
  /// Integer data used by specific kinds of rating events.
  List<int> intData;

  @ignore
  Map<String, List<dynamic>>? _info;
  @ignore
  Map<String, List<dynamic>> get info {
    if(_info == null) {
      var data = jsonDecode(_infoAsJson) as Map<String, dynamic>;
      _info = data.cast<String, List<dynamic>>();
    }
    return _info!;
  }
  set info(Map<String, List<dynamic>> v) {
    _info = v;
  }

  String _infoAsJson = "{}";
  String get infoAsJson => _info == null ? _infoAsJson : jsonEncode(_info!);
  set infoAsJson(String v) {
    _infoAsJson = v;
  }

  @ignore
  Map<String, dynamic> extraData;
  String get extraDataAsJson => jsonEncode(extraData);
  set extraDataAsJson(String v) => extraData = jsonDecode(v);
  
  DbRelativeScore score;
  DbRelativeScore matchScore;

  DbRatingEvent({
    required this.ratingChange,
    required this.oldRating,
    this.extraData = const {},
    Map<String, List<dynamic>> info = const {},
    required this.score,
    required this.matchScore,
    required this.date,
    required this.stageNumber,
    required this.entryId,
    required this.matchId,
    int doubleDataElements = 0,
    int intDataElements = 0,
  }) :
    intData = List.filled(intDataElements, 0, growable: true),
    doubleData = List.filled(doubleDataElements, 0.0, growable: true),
    _info = info,
    _infoAsJson = jsonEncode(info);

  DbRatingEvent copy() {
    var event =  DbRatingEvent(
      ratingChange: this.ratingChange,
      oldRating: this.oldRating,
      info: {}..addEntries(this.info.entries.map((e) => MapEntry(e.key, []..addAll(e.value)))),
      extraData: {}..addEntries(this.extraData.entries.map((e) => MapEntry(e.key, []..addAll(e.value)))),
      score: this.score.copy(),
      matchScore: this.matchScore.copy(),
      date: this.date,
      stageNumber: this.stageNumber,
      entryId: this.entryId,
      matchId: this.matchId,
    )..intData = ([]..addAll(intData))..doubleData = ([]..addAll(doubleData));

    event.match.value = this.match.value;
    event.owner.value = this.owner.value;

    return event;
  }
}

@embedded
class DbRelativeScore {
  /// The ordinal place represented by this score: 1 for 1st, 2 for 2nd, etc.
  int place;
  /// The ratio of this score to the winning score: 1.0 for the winner, 0.9 for a 90% finish,
  /// 0.8 for an 80% finish, etc.
  double ratio;
  @ignore
  /// A convenience getter for [ratio] * 100.
  double get percentage => ratio * 100;

  /// points holds the final score for this relative score, whether
  /// calculated or simply repeated from an attached [RawScore].
  ///
  /// In a [RelativeStageFinishScoring] match, it's the number of stage
  /// points or the total number of match points. In a [CumulativeScoring]
  /// match, it's the final points or time per stage/match.
  double points;

  DbRelativeScore({
    this.place = 0,
    this.ratio = 0,
    this.points = 0,
  });

  DbRelativeScore.fromHydrated(RelativeScore score) :
      place = score.place,
      ratio = score.ratio,
      points = score.points;

  DbRelativeScore copy() {
    return DbRelativeScore(
      place: place,
      ratio: ratio,
      points: points,
    );
  }
}