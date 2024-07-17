/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:convert';

import 'package:isar/isar.dart';
import 'package:shooting_sports_analyst/data/database/schema/match.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/interface/rating_data_source.dart';
import 'package:shooting_sports_analyst/data/ranking/project_manager.dart';
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

  /// A list of ongoing matches, which will be treated slightly differently by the rating
  /// algorithm.
  final matchesInProgress = IsarLinks<DbShootingMatch>();

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

  final dbGroups = IsarLinks<RatingGroup>();

  @ignore
  List<RatingGroup> get groups {
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

  Future<List<DbShooterRating>> ratingsForGroup(RatingGroup group) async {
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
  Future<DataSourceResult<List<RatingGroup>>> getGroups() {
    return Future.value(DataSourceResult.ok(groups));
  }
}

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
  }) : this.uuid = uuid ?? UuidV4().generate() ;
}

@collection
class DbRatingEvent {
  Id id = Isar.autoIncrement;

  @Backlink(to: 'events')
  final owner = IsarLink<DbShooterRating>();

  /// The match. See [setMatch].
  final match = IsarLink<DbShootingMatch>();

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
  Map<String, List<dynamic>> info;
  String get infoAsJson => jsonEncode(info);
  set infoAsJson(String v) => info = jsonDecode(v);

  @ignore
  Map<String, dynamic> extraData;
  String get extraDataAsJson => jsonEncode(extraData);
  set extraDataAsJson(String v) => extraData = jsonDecode(v);
  
  DbRelativeScore score;
  DbRelativeScore matchScore;

  DbRatingEvent({
    required this.ratingChange,
    required this.oldRating,
    this.info = const {},
    this.extraData = const {},
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
    doubleData = List.filled(doubleDataElements, 0.0, growable: true);

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