/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:collection/collection.dart';
import 'package:isar/isar.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/match/rating_project_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/match.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/db_rating_event.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/shooter_deduplicator.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/sport/model.dart';
import 'package:shooting_sports_analyst/util.dart';

part 'shooter_rating.g.dart';

/// DbSportRating is the database embodiment of shooter ratings. It should almost always
/// be wrapped by one of the subclasses of ShooterRating, which will wrap the various generic
/// data variables on this class.
@collection
class DbShooterRating extends Shooter with DbSportEntity {
  String sportName;

  Id id = Isar.autoIncrement;

  @ignore
  bool get isPersisted => id != Isar.autoIncrement;

  @Index(name: AnalystDatabase.knownMemberNumbersIndex, type: IndexType.hashElements)
  List<String> get dbKnownMemberNumbers => List<String>.from(knownMemberNumbers);
  set dbKnownMemberNumbers(List<String> values) => knownMemberNumbers = {}..addAll(values);

  @Index(name: AnalystDatabase.allPossibleMemberNumbersIndex, type: IndexType.hashElements)
  List<String> get dbAllPossibleMemberNumbers => List<String>.from(allPossibleMemberNumbers);
  set dbAllPossibleMemberNumbers(List<String> values) => allPossibleMemberNumbers = {}..addAll(values);

  @override
  @Index()
  String firstName;

  @override
  @Index()
  String lastName;


  @Index()
  List<String> get firstNameParts => firstName.split(RegExp(r'\s+'));
  @Index()
  List<String> get lastNameParts => lastName.split(RegExp(r'\s+'));

  @Index()
  String get deduplicatorName => ShooterDeduplicator.processName(this);

  // Additional biographical information
  String? ageCategoryName;

  @ignore
  AgeCategory? get ageCategory => sport.ageCategories.lookupByName(ageCategoryName);
  set ageCategory(AgeCategory? value) => ageCategoryName = value?.name;

  String? lastClassificationName;

  @ignore
  Classification? get lastClassification => sport.classifications.lookupByName(lastClassificationName);
  set lastClassification(Classification? c) => lastClassificationName = c?.name;

  String? divisionName;

  @ignore
  Division? get division => sport.divisions.lookupByName(divisionName);
  set division(Division? d) => divisionName = d?.name;

  @Index(composite: [CompositeIndex("group")], unique: true)
  @Backlink(to: "ratings")
  final project = IsarLink<DbRatingProject>();
  final group = IsarLink<RatingGroup>();

  /// All events belonging to this rating.
  final events = IsarLinks<DbRatingEvent>();

  /// Events added to this rating during rating calculation, but not yet persisted
  /// to the database.
  @ignore
  List<DbRatingEvent> newRatingEvents = [];

  /// The number of rating events added to this rating.
  ///
  /// Equivalent to [events.count] plus [newRatingEvents.length].
  /// Updated in the [ShooterRating.updateFromEvents] method, which
  /// is marked mustCallSuper for all of the wrapped rating subtypes.
  ///
  /// The value of this property is accurate as soon as [ShooterRating.updateFromEvents]
  /// is called, but does not reflect the actual number of rating events until
  /// the subclass implementation of [updateFromEvents] finishes adding events
  /// to the [newRatingEvents] list.
  int cachedLength = 0;

  @ignore
  int get length => cachedLength;

  // TODO: move rating events getters from elo_shooter_rating to here

  double rating;
  double error;

  /// Raw connectivity is the score before normalization/scaling.
  double rawConnectivity;
  /// Connectivity is the score after normalization/scaling.
  @Index()
  double connectivity;

  /// Match windows contain competitor information used to calculate connectivity.
  List<MatchWindow> matchWindows = [];

  /// Historical connectivity entries (raw DB list). See [historicalConnectivity].
  List<HistoricalConnectivity> dbHistoricalConnectivity = [];

  Set<HistoricalConnectivity>? _historicalConnectivity;

  /// A set of historical connectivity entries. Each entry contains the connectivity
  /// score a competitor possessed after a given match.
  @ignore
  Set<HistoricalConnectivity> get historicalConnectivity {
    if(_historicalConnectivity == null) {
      _historicalConnectivity = dbHistoricalConnectivity.toSet();
    }
    return _historicalConnectivity!;
  }
  set historicalConnectivity(Set<HistoricalConnectivity> value) {
    dbHistoricalConnectivity = value.toList();
    _historicalConnectivity = null;
  }

  /// Add a historical connectivity entry. If an entry already exists for the
  /// specified match, it is removed and replaced with the new entry.
  void addHistoricalConnectivity(HistoricalConnectivity entry) {
    if(_historicalConnectivity == null) {
      _historicalConnectivity = dbHistoricalConnectivity.toSet();
    }
    _historicalConnectivity!.remove(entry);
    _historicalConnectivity!.add(entry);
    dbHistoricalConnectivity = _historicalConnectivity!.toList();
  }

  /// Use to store algorithm-specific double data.
  List<double> doubleData = [];
  /// Use to store algorithm-specific integer data.
  List<int> intData = [];

  DateTime firstSeen;
  DateTime lastSeen;

  /// Update the connectivity of this rating, and its most recent rating event.
  ///
  /// If [save] is true, this method will make the change and save the rating to
  /// the database. If false, the caller is responsible for saving the rating.
  Future<void> updateConnectivity({
    required SourceIdsProvider match,
    required double connectivity,
    required double rawConnectivity,
    bool save = false,
  }) async {
    this.connectivity = connectivity;
    this.rawConnectivity = rawConnectivity;

    addHistoricalConnectivity(HistoricalConnectivity.create(
      matchSourceIds: match.sourceIds,
      connectivity: connectivity,
      rawConnectivity: rawConnectivity,
    ));

    if(save) {
      await AnalystDatabase().upsertDbShooterRating(this);
    }
  }

    /// Update the connectivity of this rating, and its most recent rating event.
  ///
  /// If [save] is true, this method will make the change and save the rating to
  /// the database. If false, the caller is responsible for saving the rating.
  void updateConnectivitySync({
    required SourceIdsProvider match,
    required double connectivity,
    required double rawConnectivity,
    bool save = false,
  }) {
    this.connectivity = connectivity;
    this.rawConnectivity = rawConnectivity;

    addHistoricalConnectivity(HistoricalConnectivity.create(
      matchSourceIds: match.sourceIds,
      connectivity: connectivity,
      rawConnectivity: rawConnectivity,
    ));

    if(save) {
      AnalystDatabase().upsertDbShooterRatingSync(this);
    }
  }

  Future<List<DbRatingEvent>> getEventsInWindow({int window = 0, int offset = 0}) async {
    return AnalystDatabase().getRatingEventsFor(this, limit: window, offset: offset);
  }

  List<DbRatingEvent> getEventsInWindowSync({int window = 0, int offset = 0}) {
    return AnalystDatabase().getRatingEventsForSync(this, limit: window, offset: offset);
  }

  Future<List<DbRatingEvent>> matchEvents(SourceIdsProvider match) {
    return AnalystDatabase().getRatingEventsByMatchIds(this, matchIds: match.sourceIds);
  }

  List<DbRatingEvent> matchEventsSync(SourceIdsProvider match) {
    return AnalystDatabase().getRatingEventsByMatchIdsSync(this, matchIds: match.sourceIds);
  }

  double averageFinishRatio({int window = 0, int offset = 0}) {
    var events = getEventsInWindowSync(window: window, offset: offset);
    return events.map((e) => e.score.ratio).average;
  }

  DbShooterRating({
    required this.sportName,
    required this.firstName,
    required this.lastName,
    required super.memberNumber,
    required super.female,
    required this.rating,
    required this.error,
    required this.rawConnectivity,
    required this.connectivity,
    required this.firstSeen,
    required this.lastSeen,
  }) : super(firstName: firstName, lastName: lastName);

  DbShooterRating.empty({
    required Sport sport,
    this.firstName = "",
    this.lastName = "",
    super.memberNumber = "",
    super.female = false,
    this.rating = 0.0,
    this.error = 0.0,
    this.rawConnectivity = 0.0,
    this.connectivity = 0.0,
    DateTime? firstSeen,
    DateTime? lastSeen,
    int doubleDataLength = 0,
    int intDataLength = 0,
  }) :
        this.firstSeen = firstSeen ?? DateTime(0),
        this.lastSeen = lastSeen ?? DateTime(0),
        this.sportName = sport.name,
        this.doubleData = List.filled(doubleDataLength, 0, growable: true),
        this.intData = List.filled(intDataLength, 0, growable: true),
        super(firstName: firstName, lastName: lastName);

  void copyRatingFrom(DbShooterRating other) {
    // sport won't change
    // biographical info won't change
    this.rating = other.rating;
    this.error = other.error;
    this.connectivity = other.connectivity;
    if(other.firstSeen.isBefore(this.firstSeen)) {
      this.firstSeen = other.firstSeen;
    }
    if(other.lastSeen.isAfter(this.lastSeen)) {
      this.lastSeen = other.lastSeen;
    }
    this.doubleData = []..addAll(other.doubleData);
    this.intData = []..addAll(other.intData);
  }

  @override
  String toString() {
    return "$name ${group.value?.name} ($rating)";
  }
}

typedef WrappedRatingGenerator = ShooterRating Function(DbShooterRating r);

@embedded
class MatchWindow {
  /// The source ID of the match this data is from.
  String matchSourceId;

  /// The date of the match.
  late DateTime date;

  /// The database IDs corresponding to the competitors
  /// at this match.
  List<int> uniqueOpponentIds = [];

  MatchWindow({
    this.matchSourceId = "",
    this.uniqueOpponentIds = const [],
  }) {
    this.date = DateTime.now();
  }

  MatchWindow.createFromDbMatch({
    required DbShootingMatch match,
    required List<int> uniqueOpponentIds,
    required int totalOpponents,
  }) :  this.matchSourceId = match.sourceIds.first,
        this.date = match.date,
        this.uniqueOpponentIds = uniqueOpponentIds;

  MatchWindow.createFromHydratedMatch({
    required ShootingMatch match,
    required List<int> uniqueOpponentIds,
    required int totalOpponents,
  }) : this.matchSourceId = match.sourceIds.first,
        this.date = match.date,
        this.uniqueOpponentIds = uniqueOpponentIds;

  @override
  String toString() {
    return "MatchWindow(uniqueOpponentIds: ${uniqueOpponentIds.length}, date: ${programmerYmdFormat.format(date)})";
  }
}

@embedded
class HistoricalConnectivity {
  /// A single source ID for the match for this entry, for set membership checks.
  @ignore
  String get matchSourceId => matchSourceIds.first;
  /// All source IDs for the match for this entry, to determine if this entry
  /// belongs to a particular match.
  List<String> matchSourceIds;
  double connectivity;
  double rawConnectivity;

  HistoricalConnectivity({
    this.matchSourceIds = const [],
    this.connectivity = 0.0,
    this.rawConnectivity = 0.0,
  });

  /// Create a new connectivity history entry. Use this in preference
  /// to the no-argument constructor, which is only provided for Isar.
  HistoricalConnectivity.create({
    required this.matchSourceIds,
    required this.connectivity,
    required this.rawConnectivity,
  });

  bool forMatch(SourceIdsProvider match) {
    return matchSourceIds.intersects(match.sourceIds);
  }

  operator ==(Object other) {
    if(other is HistoricalConnectivity) {
      return other.matchSourceId == matchSourceId;
    }
    return false;
  }

  @ignore
  int get hashCode => matchSourceId.hashCode;
}
