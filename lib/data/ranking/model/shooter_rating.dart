/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math';

import 'package:collection/collection.dart';
import 'package:isar/isar.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/match/rating_project_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/match.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/db_rating_event.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/shooter_deduplicator.dart';
// import 'package:shooting_sports_analyst/data/db/object/match/shooter.dart';
// import 'package:shooting_sports_analyst/data/db/object/rating/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/model/average_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/model/connected_shooter.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_change.dart';
import 'package:shooting_sports_analyst/data/sorted_list.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/shooter.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/util.dart';

var _log = SSALogger("ShooterRating");

/// ShooterRatings are convenience wrappers around [DbShooterRating].
/// 
/// They hold some common functionality for all shooter ratings. Concrete
/// implementations for different rating types can provide cleaner access
/// to the underlying data, especially for the intData and doubleData arrays
/// on DbShooterRating.
abstract class ShooterRating<T extends RatingEvent> extends Shooter with DbSportEntity {
  String sportName;

  String get firstName => wrappedRating.firstName;
  set firstName(String n) => wrappedRating.firstName = n;

  String get lastName => wrappedRating.lastName;
  set lastName(String n) => wrappedRating.lastName = n;

  set memberNumber(String m) {
    super.memberNumber = m;
    var deduplicator = sport.shooterDeduplicator;
    if(deduplicator != null) {
      allPossibleMemberNumbers.addAll(deduplicator.alternateForms(m));
    }
  }

  @override
  Set<String> get allPossibleMemberNumbers => wrappedRating.allPossibleMemberNumbers;
  @override
  set allPossibleMemberNumbers(Set<String> s) => wrappedRating.allPossibleMemberNumbers = s;
  
  /// The DB rating object backing this rating. If its ID property
  /// is [Isar.autoIncrement], it is assumed that the rating has not
  /// yet been persisted to the database. The database code will update
  /// the backing object when saving it.
  ///
  /// When creating a new shooter rating, you should create a
  /// DbShooterRating to store its data.
  DbShooterRating wrappedRating;

  RatingGroup get group {
    if(!wrappedRating.group.isLoaded) {
      wrappedRating.group.loadSync();
    }

    return wrappedRating.group.value!;
  }

  /// Whether the data contained by [wrappedRating] has been persisted.
  bool get isPersisted => wrappedRating.isPersisted;
  
  /// The number of events over which trend/variance are calculated.
  static const baseTrendWindow = 30;

  /// The number of stages which makes up a nominal match.
  static const trendStagesPerMatch = 6;

  /// The time after which a shooter will no longer be counted in connectedness.
  static const connectionExpiration = const Duration(days: 60);
  static const connectionPercentGain = 0.01;
  static const baseConnectedness = 100.0;
  static const maxConnections = 40;

  Division? get division => wrappedRating.division;
  set division(Division? d) => wrappedRating.division = d;

  Classification? get lastClassification => wrappedRating.lastClassification;
  set lastClassification(Classification? c) => wrappedRating.lastClassification = c;

  DateTime get firstSeen => wrappedRating.firstSeen;
  set firstSeen(DateTime d) => wrappedRating.firstSeen = d;

  DateTime get lastSeen => wrappedRating.lastSeen;
  set lastSeen(DateTime d) => wrappedRating.lastSeen = d;

  double get rating => wrappedRating.rating;
  set rating(double v) => wrappedRating.rating = v;

  /// All of the meaningful rating events in this shooter's history, ordered
  /// from newest to oldest.
  ///
  /// A meaningful rating event is an event where the shooter competed against
  /// at least one other person.
  List<T> get ratingEvents {
    if(_ratingEvents == null) {
      var events = AnalystDatabase().getRatingEventsForSync(wrappedRating);
      _ratingEvents = events.map((e) => wrapEvent(e)).toList();
    }

    List<T> newRatingEvents = [];
    if(wrappedRating.newRatingEvents.isNotEmpty) {
      var unpersistedEvents = wrappedRating.newRatingEvents.map((e) => wrapEvent(e));
      newRatingEvents.addAll(unpersistedEvents);
    }

    var out = [..._ratingEvents!, ...newRatingEvents];
    return out;
  }

  List<T>? _ratingEvents = null;

  /// Called by the rating project loader when rating events change, so that
  /// the shooter rating can clear any relevant caches.
  void ratingEventsChanged() {
    _ratingEvents = null;
    _lastMatchChange = null;
    _length = null;
  }

  /// All of the empty rating events in this shooter's history where the
  /// shooter competed against nobody else.
  List<T> get emptyRatingEvents;

  /// All of the rating events in this shooter's history, combining
  /// [emptyRatingEvents] and [ratingEvents]. No order is guaranteed.
  List<T> get combinedRatingEvents;

  /// Provide a typed RatingEvent wrapper for a DbRatingEvent to allow for
  /// enhanced DB-based features without knowledge of the underlying types.
  T wrapEvent(DbRatingEvent e);

  /// Returns the shooter's rating after accounting for the given event.
  ///
  /// If the shooter did not participate in the match, returns
  /// the shooter's latest rating prior to the match.
  ///
  /// If the shooter participated in the match but not the given
  /// stage (due to DQ, DNF, etc.), returns the shooter's rating
  /// prior to the match.
  ///
  /// If stage is not provided, returns the shooter's rating after
  /// the match.
  ///
  /// If the shooter was not rated prior to the match and none of the
  /// above cases apply, returns the shooter's current rating.
  double ratingForEvent(ShootingMatch match, MatchStage? stage, {bool beforeMatch = false}) {
    RatingEvent? candidateEvent;
    for(var e in ratingEvents) {
      if(e.match.sourceIds.containsAny(match.sourceIds) && (candidateEvent == null || beforeMatch)) {
        if(stage == null) {
          // Because we're going backward, this will get the last change from the
          // match.
          candidateEvent = e;

          // Continue setting candidateEvent until we get to an event that isn't
          // from the desired match, at which point we'll fall out via the
          // break at the end of the loop, and return the oldRating because of
          // candidateEvent.
          if(beforeMatch) {
            continue;
          }
        }
        else if(stage.name == e.stage?.name) {
          candidateEvent = e;
        }
      }
      else if(candidateEvent == null && e.match.date!.isBefore(match.date!)) {
        candidateEvent = e;
      }

      if(candidateEvent != null) break;
    }

    if(candidateEvent != null) {
      return beforeMatch ? candidateEvent.oldRating : candidateEvent.newRating;
    }
    else {
      return rating;
    }
  }

  /// Returns the shooter's rating as of the given date.
  ///
  /// If the shooter's rating history starts after the given date,
  /// this returns the shooter's earliest rating.
  double ratingForDate(DateTime date) {
    // Find the first event that occurred before the given date.
    var event = AnalystDatabase().getRatingEventsForSync(wrappedRating, before: date, limit: 1).firstOrNull;
    if(event != null) {
      return event.newRating;
    }
    else {
      return rating;
    }
  }

  /// Returns the shooter's rating change for the given event.
  ///
  /// If stage is null, returns the shooter's total rating change
  /// for the given match. If stage is not null, returns the rating
  /// change for the given stage.
  ///
  /// If the shooter's rating did not change at the given event,
  /// returns null.
  double? changeForEvent(ShootingMatch match, MatchStage? stage) {
    var eventsFromMatch = AnalystDatabase().getRatingEventsByMatchIdsSync(wrappedRating, matchIds: match.sourceIds);

    if(eventsFromMatch.isEmpty) return null;
    else return eventsFromMatch.map((e) => e.ratingChange).sum;
  }

  double? ratingAtEvent(ShootingMatch match, MatchStage? stage) {
    T? latest;

    // TODO: this can be much faster with a DB query
    // Add it to datasource, too, since we're gonna want it in eventual
    // server mode, probably.
    var eventsFromMatch = AnalystDatabase().getRatingEventsByMatchIdsSync(wrappedRating, matchIds: match.sourceIds);
    for(var e in eventsFromMatch) {
      if(stage == null) {
        latest = wrapEvent(e);
        break;
      }
      else {
        if(e.stageNumber == stage.stageId) {
          latest = wrapEvent(e);
          break;
        }
      }
    }

    return latest?.newRating;
  }

  @ignore 
  int? _length = null;
  @ignore
  int get length {
    if(_length != null) return _length!;
    _length = wrappedRating.length;
    return _length!;
  }

  void updateFromEvents(List<RatingEvent> events);

  AverageRating averageRating({int window = ShooterRating.baseTrendWindow, List<double>? preloadedRatings}) {
    double lowestPoint = rating;
    double highestPoint = rating;

    // The list of ratings, from oldest to newest.
    // We need to reverse the database query, because we need order.desc to get the N most recent,
    // but we want to iterate from oldest to newest.
    List<double> ratings = preloadedRatings 
      ?? AnalystDatabase().getRatingEventRatingForSync(wrappedRating, limit: window, offset: 0, order: Order.descending, newRating: false).reversed.toList();
    List<double> intermediateRatings = [];

    // Iterate from oldest to newest (although it doesn't really matter).
    double firstRating = 0.0;
    if(ratings.isNotEmpty) {
      firstRating = ratings.first;
    }
    // We want to get a tail window here because preloadedRatings might be longer than required
    for(var rating in ratings.getTailWindow(window)) {
      var intermediateRating = rating;
      if(intermediateRating < lowestPoint) lowestPoint = intermediateRating;
      if(intermediateRating > highestPoint) highestPoint = intermediateRating;
      intermediateRatings.add(intermediateRating);
    }

    var intermediateAverage = intermediateRatings.isEmpty ? 0.0 : intermediateRatings.average;
    return AverageRating(firstRating: firstRating, minRating: lowestPoint, maxRating: highestPoint, averageOfIntermediates: intermediateAverage, window: window);
  }

  List<T> eventsWithWindow({int window = baseTrendWindow, int offset = 0}) {
    return AnalystDatabase().getRatingEventsForSync(wrappedRating, limit: window, offset: offset).map((e) => wrapEvent(e)).toList();
  }

  double get connectivity => wrappedRating.connectivity;
  set connectivity(double v) => wrappedRating.connectivity = v;

  double get rawConnectivity => wrappedRating.rawConnectivity;
  set rawConnectivity(double v) => wrappedRating.rawConnectivity = v;

  void updateTrends(List<RatingEvent> changes);
  double get trend => rating - averageRating().firstRating;

  void copyRatingFrom(covariant ShooterRating other) {
    this.lastClassification = other.lastClassification;
    this.lastSeen = other.lastSeen;
    this.wrappedRating.copyRatingFrom(other.wrappedRating);
    this.knownMemberNumbers.add(other.originalMemberNumber);
  }

  double? _lastMatchChange = null;
  double get lastMatchChange {
    if(_lastMatchChange != null) return _lastMatchChange!;
    if(length == 0) return 0;

    var lastEvent = AnalystDatabase().getRatingEventsForSync(wrappedRating, limit: 1).first;
    _lastMatchChange = matchChange(DbShootingMatch.sourcePlaceholder(sport: sport, sourceCode: "<n/a>", sourceIds: [lastEvent.matchId]));
    return _lastMatchChange!;
  }

  double matchChange(SourceIdsProvider match) {
    var matchEvents = this.matchEvents(match);
    if (matchEvents.isEmpty) {
      return 0;
    }
    return matchEvents.map((e) => e.ratingChange).sum;
  }

  List<T> matchEvents(SourceIdsProvider match) {
    var events = AnalystDatabase().getRatingEventsByMatchIdsSync(wrappedRating, matchIds: match.sourceIds);
    return events.map((e) => wrapEvent(e)).toList();
  }

  List<MatchHistoryEntry> careerHistory() {
    List<MatchHistoryEntry> history = [];

    ShootingMatch? lastMatch;
    for(var e in ratingEvents) {
      if(e.match != lastMatch) {
        var division = e.match.shooters.firstWhereOrNull((element) => this.equalsShooter(element))?.division;
        if(division == null) {
          _log.w("Unable to match division for $this at ${e.match}");
          lastMatch = e.match;
          continue;
        }
        history.add(MatchHistoryEntry(
          match: e.match, shooter: this, divisionEntered: division,
          ratingChange: changeForEvent(e.match, null) ?? 0,
        ));
        lastMatch = e.match;
      }
    }

    return history;
  }

  void copyVitalsFrom(covariant ShooterRating other) {
    this.firstName = other.firstName;
    this.lastName = other.lastName;
    this.knownMemberNumbers = {}..addAll(other.knownMemberNumbers);
  }

  ShooterRating(MatchEntry shooter, {
    required Sport sport,
    required DateTime date,
    required int doubleDataElements,
    required int intDataElements
  }) :
      this.wrappedRating = DbShooterRating.empty(
        sport: sport,
        intDataLength: intDataElements,
        doubleDataLength: doubleDataElements,
      ),
      this.sportName = sport.name,
      super(firstName: shooter.firstName, lastName: shooter.lastName) {
    this.lastClassification = shooter.classification ?? sport.classifications.fallback();
    this.firstSeen = date;
    this.lastSeen = date;
    super.copyVitalsFrom(shooter);
  }

  ShooterRating.fromRating(ShooterRating shooter, {required Sport sport, DateTime? date}) :
        this.wrappedRating = DbShooterRating.empty(sport: sport),
        this.sportName = sport.name,
        super(firstName: shooter.firstName, lastName: shooter.lastName) {
    this.lastClassification = shooter.lastClassification;
    this.firstSeen = shooter.firstSeen;
    this.lastSeen = date ?? DateTime.now();
    super.copyVitalsFrom(shooter);
  }

  ShooterRating.wrapDbRating(DbShooterRating rating) :
      this.wrappedRating = rating,
      this.sportName = rating.sportName,
      super(firstName: rating.firstName, lastName: rating.lastName) {
    super.copyVitalsFrom(rating);
  }


  @override
  bool equalsShooter(Shooter other) {
    if(super.equalsShooter(other)) return true;
    var numberProcessor = sport.shooterDeduplicator?.processNumber ?? ShooterDeduplicator.normalizeNumberBasic;

    for(var number in knownMemberNumbers) {
      var processed = numberProcessor(number);
      for(var otherNumber in other.knownMemberNumbers) {
        var otherProcessed = numberProcessor(otherNumber);
        if(processed == otherProcessed) return true;
      }
    }

    return false;
  }

  // ShooterRating.fromVitals(DbShooterRating rating) :
  //     this.lastClassification = rating.lastClassification,
  //     this.firstSeen = throw UnimplementedError(),
  //     this.lastSeen = rating.lastSeen {
  //   super.copyDbVitalsFrom(rating);
  // }

  ShooterRating.copy(ShooterRating other) :
      this.wrappedRating = DbShooterRating.empty(sport: other.sport),
      this.sportName = other.sportName,
      super(firstName: other.firstName, lastName: other.lastName)
  {
    this.knownMemberNumbers = {}..addAll(other.knownMemberNumbers);
    this.lastClassification = other.lastClassification;
    this.lastSeen = other.lastSeen;
    this.firstSeen = other.firstSeen;
    super.copyVitalsFrom(other);
  }
}

class MatchHistoryEntry {
  ShootingMatch match;
  DateTime get date => match.date!;
  Division divisionEntered;
  double ratingChange;
  late int place;
  late int competitors;
  late double finishRatio;
  String get percentFinish => finishRatio.asPercentage();

  MatchHistoryEntry({
    required this.match,
    required ShooterRating shooter,
    required this.divisionEntered,
    required this.ratingChange,
  }) {
    var scores = match.getScores(shooters: match.filterShooters(filterMode: FilterMode.and, divisions: [divisionEntered], allowReentries: false));
    var score = scores.values.firstWhereOrNull((element) => shooter.equalsShooter(element.shooter));

    this.place = score!.place;
    this.finishRatio = score.ratio;
    this.competitors = scores.length;
  }

  @override
  String toString() {
    return "${match.name} (${divisionEntered.shortDisplayName}): $place/$competitors ($percentFinish%)";
  }
}