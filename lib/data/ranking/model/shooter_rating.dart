/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math';

import 'package:collection/collection.dart';
import 'package:isar/isar.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
// import 'package:shooting_sports_analyst/data/db/object/match/shooter.dart';
// import 'package:shooting_sports_analyst/data/db/object/rating/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/model/average_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/model/connected_shooter.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_change.dart';
import 'package:shooting_sports_analyst/data/ranking/rater.dart';
import 'package:shooting_sports_analyst/data/sorted_list.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/shooter.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/util.dart';

var _log = SSALogger("ShooterRating");

/// ShooterRatings are convenience wrappers around [DbShooterRating], which
///
abstract class ShooterRating extends Shooter with DbSportEntity {
  String sportName;

  String get firstName => wrappedRating.firstName;
  set firstName(String n) => wrappedRating.firstName = n;

  String get lastName => wrappedRating.lastName;
  set lastName(String n) => wrappedRating.lastName = n;
  
  /// The DB rating object backing this rating. If its ID property
  /// is [Isar.autoIncrement], it is assumed that the rating has not
  /// yet been persisted to the database. The database code will update
  /// the backing object when saving it.
  ///
  /// When creating a new shooter rating, you should create a
  /// DbShooterRating to store its data.
  DbShooterRating wrappedRating;

  DbRatingGroup get group {
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

  /// All of the meaningful rating events in this shooter's history.
  ///
  /// A meaningful rating event is an event where the shooter competed against
  /// at least one other person.
  List<RatingEvent> get ratingEvents;

  /// All of the empty rating events in this shooter's history where the
  /// shooter competed against nobody else.
  List<RatingEvent> get emptyRatingEvents;

  /// All of the rating events in this shooter's history, combining
  /// [emptyRatingEvents] and [ratingEvents]. No order is guaranteed.
  List<RatingEvent> get combinedRatingEvents;

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
    for(var e in ratingEvents.reversed) {
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

  /// Returns the shooter's rating change for the given event.
  ///
  /// If stage is null, returns the shooter's total rating change
  /// for the given match. If stage is not null, returns the rating
  /// change for the given stage.
  ///
  /// If the shooter's rating did not change at the given event,
  /// returns null.
  double? changeForEvent(ShootingMatch match, MatchStage? stage) {
    List<RatingEvent> events = [];
    for(var e in ratingEvents.reversed) {
      if(stage == null && e.match.sourceIds.containsAny(match.sourceIds)) {
        events.add(e);
      }
      else if(stage != null && e.match.sourceIds.containsAny(match.sourceIds) && e.stage?.name == stage.name) {
        events.add(e);
      }
    }

    if(events.isEmpty) return null;
    else return events.map((e) => e.ratingChange).sum;
  }

  double? changeForNewEvent(ShootingMatch match, MatchStage? stage) {
    List<RatingEvent> events = [];
    for(var e in ratingEvents.reversed) {
      if(stage == null && e.match.sourceIds.first == match.sourceIds.first) {
        events.add(e);
      }
      else if(stage != null && e.match.sourceIds.first == match.sourceIds.first && e.stage?.name == stage.name) {
        events.add(e);
      }
    }

    if(events.isEmpty) return null;
    else return events.map((e) => e.ratingChange).sum;
  }

  @ignore
  int get length => ratingEvents.length;

  void updateFromEvents(List<RatingEvent> events);

  AverageRating averageRating({int window = ShooterRating.baseTrendWindow}) {
    double runningRating = rating;
    double lowestPoint = rating;
    double highestPoint = rating;

    late List<RatingEvent> ratingEventList;
    List<double> intermediateRatings = [];
    if(window > ratingEvents.length) ratingEventList = ratingEvents;
    else ratingEventList = ratingEvents.sublist(ratingEvents.length - window);

    for(var event in ratingEventList.reversed) {
      var intermediateRating = runningRating - event.ratingChange;
      if(intermediateRating < lowestPoint) lowestPoint = intermediateRating;
      if(intermediateRating > highestPoint) highestPoint = intermediateRating;
      intermediateRatings.add(intermediateRating);
      runningRating = intermediateRating;
    }

    var intermediateAverage = intermediateRatings.isEmpty ? 0.0 : intermediateRatings.average;
    return AverageRating(firstRating: runningRating, minRating: lowestPoint, maxRating: highestPoint, averageOfIntermediates: intermediateAverage, window: window);
  }

  List<RatingEvent> eventsWithWindow({int window = baseTrendWindow, int offset = 0}) {
    if((window + offset) >= ratingEvents.length) {
      if(offset < (ratingEvents.length)) return ratingEvents.sublist(0, ratingEvents.length - offset);
      else return ratingEvents;
    }
    else {
      return ratingEvents.sublist(ratingEvents.length - (window + offset), ratingEvents.length - offset);
    }
  }

  double averagePercentFinishes({int window = baseTrendWindow, int offset = 0}) {
    double percentFinishes = 0.0;

    var events = eventsWithWindow(window: window, offset: offset);
    if(events.isEmpty) return 0;

    for(var e in events) {
      percentFinishes += e.score.ratio;
    }

    return percentFinishes / events.length;
  }

  @ignore
  /// The shooters off of whom this shooter's connectedness is based.
  SortedList<ConnectedShooter> connectedShooters = SortedList(comparator: ConnectedShooter.dateComparisonClosure);
  double _connectedness = ShooterRating.baseConnectedness;
  double get connectedness => _connectedness;

  void updateConnectedness() {
    var c = ShooterRating.baseConnectedness;
    for(var connection in connectedShooters.iterable) {
      // Our connectedness increases by the connectedness of the other shooter, minus
      // the connectedness they get from us.
      var change = (connection.connectedness * ShooterRating.connectionPercentGain) - (_connectedness * ShooterRating.connectionPercentGain * connectionPercentGain);

      // Fewer points for connecting with someone without a lot of ratings
      var scale = min(1.0, connection.shooter.ratingEvents.length / ShooterRating.baseTrendWindow);

      // Fewer points if you don't have a lot of ratings
      // if(ratingEvents.length < baseTrendWindow) {
      //   scale = min(1.0, max(0.25, scale * ratingEvents.length / baseTrendWindow));
      // }

      change = change * scale;

      c += change;
    }

    _connectedness = c;
  }

  void updateConnections(DateTime now, List<ShooterRating> encountered) {
    // TODO: change algorithm here, maybe?
    // connectedness is the number of unique shooters a shooter has shot against recently,
    // as a percentage of the count of shooters in the DB
    int added = 0;
    int updated = 0;

    DateTime oldestAllowed = now.subtract(connectionExpiration);
    Map<ShooterRating, ConnectedShooter> connMap = {};
    for(var connection in connectedShooters.asIterable) {
      if(connection.lastSeen.isAfter(oldestAllowed)) {
        connMap[connection.shooter] = connection;
      }
      else {
        // This is kosher because asIterable returns a copy
        connectedShooters.remove(connection);
      }
    }

    var lowValueConnections = SortedList<ConnectedShooter>(comparator: (a, b) => a.connectedness.compareTo(b.connectedness));
    lowValueConnections.addAll(connectedShooters.iterable);

    for(var shooter in encountered) {
      var currentConnection = connMap[shooter];
      if(currentConnection != null) {
        currentConnection.connectedness = shooter.connectedness;
        currentConnection.lastSeen = now;
        updated++;
      }
      else if(shooter != this) {
        // No need to add this connection if our list is full and it's worst than our current worst connection.
        if(lowValueConnections.length >= maxConnections) {
          var worstConnection = lowValueConnections.first;
          if(shooter.connectedness < worstConnection.connectedness) continue;
        }

        var newConnection = ConnectedShooter(
          shooter: shooter,
          connectedness: shooter.connectedness,
          lastSeen: now,
        );
        connectedShooters.add(newConnection);
        lowValueConnections.add(newConnection);
        added++;
      }
      else {
        // ignoring self
      }
    }

    if(connectedShooters.length > maxConnections) {
      int nToRemove = connectedShooters.length - maxConnections;
      var sorted = lowValueConnections;

      int i = 0;
      for(var connection in sorted.iterable) {
        if(i >= nToRemove) break;

        connectedShooters.remove(connection);
        i++;
      }
    }
  }

  void updateTrends(List<RatingEvent> changes);
  double get trend => rating - averageRating().firstRating;

  void copyRatingFrom(covariant ShooterRating other) {
    this._connectedness = other._connectedness;
    this.lastClassification = other.lastClassification;
    this.lastSeen = other.lastSeen;
    this.wrappedRating.copyRatingFrom(other.wrappedRating);
    this.knownMemberNumbers.add(other.originalMemberNumber);
    this.connectedShooters = SortedList(comparator: ConnectedShooter.dateComparisonClosure)..addAll(other.connectedShooters.map((e) => ConnectedShooter.copy(e)));
  }

  double get lastMatchChange {
    if(length == 0) return 0;

    var lastMatch = ratingEvents.last.match;
    return matchChange(lastMatch);
  }

  double matchChange(ShootingMatch match) {
    double change = ratingEvents.where((e) => e.match == match)
        .map((e) => e.ratingChange)
        .reduce((a, b) => a + b);
    return change;
  }

  List<MatchHistoryEntry> careerHistory() {
    List<MatchHistoryEntry> history = [];

    ShootingMatch? lastMatch;
    for(var e in ratingEvents) {
      if(e.match != lastMatch) {
        var division = e.match.shooters.firstWhereOrNull((element) => this.equalsShooter(element))?.division;
        if(division == null) {
          _log.w("Unable to match division for $this at ${e.match}");
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

    for(var number in knownMemberNumbers) {
      var processed = Rater.processMemberNumber(number);

      if(other is ShooterRating) {
        for(var otherNumber in other.knownMemberNumbers) {
          var otherProcessed = Rater.processMemberNumber(otherNumber);
          if(processed == otherProcessed) return true;
        }
      }
      else {
        if (processed == other.memberNumber) return true;
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
      this._connectedness = other._connectedness,
      this.connectedShooters = SortedList(comparator: ConnectedShooter.dateComparisonClosure)..addAll(other.connectedShooters.map((e) => ConnectedShooter.copy(e))),
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