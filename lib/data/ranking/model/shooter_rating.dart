import 'dart:math';

import 'package:collection/collection.dart';
import 'package:uspsa_result_viewer/data/db/object/match/shooter.dart';
import 'package:uspsa_result_viewer/data/db/object/rating/shooter_rating.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/ranking/model/average_rating.dart';
import 'package:uspsa_result_viewer/data/ranking/model/connected_shooter.dart';
import 'package:uspsa_result_viewer/data/ranking/model/rating_change.dart';
import 'package:uspsa_result_viewer/data/sorted_list.dart';

abstract class ShooterRating extends Shooter {
  /// The number of events over which trend/variance are calculated.
  static const baseTrendWindow = 30;

  /// The number of stages which makes up a nominal match.
  static const trendStagesPerMatch = 6;

  /// The time after which a shooter will no longer be counted in connectedness.
  static const connectionExpiration = const Duration(days: 60);
  static const connectionPercentGain = 0.01;
  static const baseConnectedness = 100.0;
  static const maxConnections = 40;

  Classification lastClassification;
  DateTime lastSeen;

  double get rating;

  List<RatingEvent> get ratingEvents;

  /// Alternate member numbers this shooter is known by.
  List<String> alternateMemberNumbers = [];

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

    return AverageRating(firstRating: runningRating, minRating: lowestPoint, maxRating: highestPoint, averageOfIntermediates: intermediateRatings.sum / intermediateRatings.length, window: window);
  }

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

      // if(Rater.processMemberNumber(shooter.memberNumber) == "122755") {
      //   debugPrint("${connection.shooter.shooter.getName(suffixes: false)} contributed $change to ${shooter.getName(suffixes: false)}");
      // }

      c += change;
    }

    // if(Rater.processMemberNumber(shooter.memberNumber) == "122755") {
    //   debugPrint("${shooter.getName(suffixes: false)} changed to $c");
    // }

    _connectedness = c;
  }

  void updateConnections(DateTime now, List<ShooterRating> encountered) {
    // if(Rater.processMemberNumber(this.shooter.memberNumber) == "122755")  print("Shooter $this has ${connectedShooters.length} connections, encountered ${encountered.length} shooters");
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

    for(var shooter in encountered) {
      var currentConnection = connMap[shooter];
      if(currentConnection != null) {
        lowValueConnections.add(currentConnection);

        // if(Rater.processMemberNumber(this.shooter.memberNumber) == "122755")  print("Updated connection to $shooter");
        currentConnection.connectedness = shooter.connectedness;
        currentConnection.lastSeen = now;
        updated++;
      }
      else if(shooter != this) {
        // if(Rater.processMemberNumber(this.shooter.memberNumber) == "122755")  print("Added connection to $shooter");
        var newConnection = ConnectedShooter(
          shooter: shooter,
          connectedness: shooter.connectedness,
          lastSeen: now,
        );
        connectedShooters.add(
          newConnection
        );
        lowValueConnections.add(newConnection);
        added++;
      }
      else {
        // if(Rater.processMemberNumber(this.shooter.memberNumber) == "122755") print("Ignoring self");
      }
    }
    // if(Rater.processMemberNumber(this.shooter.memberNumber) == "122755") print("Now has ${connectedShooters.length} connections, added $added, updated $updated of ${encountered.length - 1}");

    if(connectedShooters.length > maxConnections) {
      int nToRemove = connectedShooters.length - maxConnections;
      var sorted = lowValueConnections;

      int i = 0;
      for(var connection in sorted.iterable) {
        if(i >= nToRemove) break;

        connectedShooters.remove(connection);
        i++;
      }

      // if(Rater.processMemberNumber(this.shooter.memberNumber) == "122755") print("${nToRemove} were above the connection limit\n");
    }
  }

  void updateTrends(List<RatingEvent> changes);
  double get trend => rating - averageRating().firstRating;

  void copyRatingFrom(covariant ShooterRating other) {
    this._connectedness = other._connectedness;
    this.lastClassification = other.lastClassification;
    this.lastSeen = other.lastSeen;
    if(!this.alternateMemberNumbers.contains(other.originalMemberNumber)) {
      this.alternateMemberNumbers.add(other.originalMemberNumber);
    }
    this.connectedShooters = SortedList(comparator: ConnectedShooter.dateComparisonClosure)..addAll(other.connectedShooters.map((e) => ConnectedShooter.copy(e)));
  }

  double get lastMatchChange {
    if(length == 0) return 0;

    var lastMatch = ratingEvents.last.match;
    return matchChange(lastMatch);
  }

  double matchChange(PracticalMatch match) {
    double change = ratingEvents.where((e) => e.match == match)
        .map((e) => e.ratingChange)
        .reduce((a, b) => a + b);
    return change;
  }

  void copyVitalsFrom(covariant ShooterRating other) {
    this.firstName = other.firstName;
    this.lastName = other.lastName;
    this.alternateMemberNumbers = other.alternateMemberNumbers;
  }

  ShooterRating(Shooter shooter, {DateTime? date}) :
      this.lastClassification = shooter.classification ?? Classification.U,
      this.lastSeen = date ?? DateTime.now() {
    super.copyVitalsFrom(shooter);
  }

  ShooterRating.fromVitals(DbShooterRating rating) :
      this.lastClassification = rating.lastClassification,
      this.lastSeen = rating.lastSeen {
    super.copyDbVitalsFrom(rating);
  }

  ShooterRating.copy(ShooterRating other) :
      this.lastClassification = other.lastClassification,
      this._connectedness = other._connectedness,
      this.lastSeen = other.lastSeen,
      this.alternateMemberNumbers = other.alternateMemberNumbers,
      this.connectedShooters = SortedList(comparator: ConnectedShooter.dateComparisonClosure)..addAll(other.connectedShooters.map((e) => ConnectedShooter.copy(e)))
  {
    super.copyVitalsFrom(other);
  }
}