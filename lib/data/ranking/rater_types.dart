import 'dart:collection';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/ranking/rater.dart';
import 'package:uspsa_result_viewer/data/sorted_list.dart';

class ShooterRating {
  /// The number of events over which trend/variance are calculated.
  static const baseTrendWindow = 30;

  /// The number of stages which makes up a nominal match.
  static const trendStagesPerMatch = 6;

  /// The time after which a shooter will no longer be counted in connectedness.
  static const connectionExpiration = const Duration(days: 60);
  static const connectionPercentGain = 0.01;
  static const baseConnectedness = 100.0;
  static const maxConnections = 40;

  final Shooter shooter;
  double rating;
  double variance = 0;
  double trend = 0;

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

    return AverageRating(minRating: lowestPoint, maxRating: highestPoint, averageOfIntermediates: intermediateRatings.sum / intermediateRatings.length, window: window);
  }

  List<RatingEvent> ratingEvents = [];

  /// The shooters off of whom this shooter's connectedness is based.
  SortedList<ConnectedShooter> connectedShooters = SortedList(comparator: ConnectedShooter.dateComparisonClosure);
  double _connectedness = baseConnectedness;
  double get connectedness => _connectedness;

  // TODO: have this return the change, apply at the end
  void updateConnectedness() {
    var c = baseConnectedness;
    for(var connection in connectedShooters.asIterable) {
      // Our connectedness increases by the connectedness of the other shooter, minus
      // the connectedness they get from us.
      var change = (connection.connectedness * connectionPercentGain) - (_connectedness * connectionPercentGain * connectionPercentGain);

      // Fewer points for connecting with someone without a lot of ratings
      var scale = min(1.0, connection.shooter.ratingEvents.length / baseTrendWindow);

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
    for(var shooter in encountered) {
      var currentConnection = connectedShooters.firstWhereOrNull((connection) => connection.shooter == shooter);
      if(currentConnection != null) {
        // if(Rater.processMemberNumber(this.shooter.memberNumber) == "122755")  print("Updated connection to $shooter");
        currentConnection.connectedness = shooter.connectedness;
        currentConnection.lastSeen = now;
        updated++;
      }
      else if(shooter != this) {
        // if(Rater.processMemberNumber(this.shooter.memberNumber) == "122755")  print("Added connection to $shooter");
        connectedShooters.add(
          ConnectedShooter(
            shooter: shooter,
            connectedness: shooter.connectedness,
            lastSeen: now,
          )
        );
        added++;
      }
      else {
        // if(Rater.processMemberNumber(this.shooter.memberNumber) == "122755") print("Ignoring self");
      }
    }
    // if(Rater.processMemberNumber(this.shooter.memberNumber) == "122755") print("Now has ${connectedShooters.length} connections, added $added, updated $updated of ${encountered.length - 1}");

    Set<ConnectedShooter> outdated = Set();
    DateTime oldestAllowed = now.subtract(connectionExpiration);
    for(var connection in connectedShooters.asIterable) {
      if(connection.lastSeen.isBefore(oldestAllowed)) {
        outdated.add(connection);
      }
    }

    // if(Rater.processMemberNumber(this.shooter.memberNumber) == "122755") print("${outdated.length} were outdated");
    connectedShooters.removeAll(outdated);

    if(connectedShooters.length > maxConnections) {
      int nToRemove = connectedShooters.length - maxConnections;
      var sorted = connectedShooters.sorted((a, b) => a.connectedness.compareTo(b.connectedness));

      int i = 0;
      for(var connection in sorted) {
        if(i >= nToRemove) break;

        connectedShooters.remove(connection);

        i++;
      }

      // if(Rater.processMemberNumber(this.shooter.memberNumber) == "122755") print("${nToRemove} were above the connection limit\n");
    }
  }

  ShooterRating(this.shooter, this.rating);

  void updateTrends(double totalChange) {
    var trendWindow = min(ratingEvents.length, baseTrendWindow);

    if(trendWindow == 0) {
      return;
    }

    var totalVariance = variance * (trendWindow - 1) + totalChange.abs();
    variance = totalVariance / (trendWindow.toDouble());

    var totalTrend = trend * (trendWindow - 1) + (totalChange >= 0 ? 1 : -1);
    trend = totalTrend / (trendWindow);

    // if(Rater.processMemberNumber(shooter.memberNumber) == "128393") {
    //   debugPrint("Trends for ${shooter.lastName}");
    //   debugPrint("$totalVariance / $trendWindow = $variance");
    //   debugPrint("$totalTrend / $trendWindow = $trend");
    // }
  }
  
  void copyRatingFrom(ShooterRating other) {
    this.rating = other.rating;
    this.variance = other.variance;
    this.trend = other.trend;
    this._connectedness = other._connectedness;
    this.connectedShooters = SortedList(comparator: ConnectedShooter.dateComparisonClosure)..addAll(other.connectedShooters.map((e) => ConnectedShooter.copy(e)));
    this.ratingEvents = other.ratingEvents.map((e) => RatingEvent.copy(e)).toList();
  }

  ShooterRating.copy(ShooterRating other) :
      this.shooter = other.shooter,
      this.rating = other.rating,
      this.variance = other.variance,
      this.trend = other.trend,
      this._connectedness = other._connectedness,
      this.connectedShooters = SortedList(comparator: ConnectedShooter.dateComparisonClosure)..addAll(other.connectedShooters.map((e) => ConnectedShooter.copy(e))),
      this.ratingEvents = other.ratingEvents.map((e) => RatingEvent.copy(e)).toList();

  @override
  String toString() {
    return "${shooter.getName(suffixes: false)} ${rating.round()} ($hashCode)";
  }
}

class AverageRating {
  final double minRating;
  final double maxRating;
  final double averageOfIntermediates;
  final int window;

  double get averageOfMinMax => (minRating + maxRating) / 2;

  AverageRating({
    required this.minRating,
    required this.maxRating,
    required this.averageOfIntermediates,
    required this.window,
  });
}

class RatingChange {
  final double change;
  final List<String> info;

  RatingChange({required this.change, this.info = const []});
}

class RatingEvent {
  String eventName;
  RelativeScore score;
  double ratingChange;
  List<String> info;

  RatingEvent({required this.eventName, required this.score, this.ratingChange = 0, this.info = const []});

  RatingEvent.copy(RatingEvent other) :
      this.eventName = other.eventName,
      this.score = other.score,
      this.ratingChange = other.ratingChange,
      this.info = [...other.info];
}

class ConnectedShooter {
  static final dateComparisonClosure = (ConnectedShooter a, ConnectedShooter b) => a.lastSeen.compareTo(b.lastSeen);

  /// The other shooter.
  final ShooterRating shooter;

  /// The other shooter's current connectedness.
  double connectedness;
  //double get connectedness => shooter.connectedness;

  /// The last time this shooter and the other shooter saw each other.
  DateTime lastSeen;

  ConnectedShooter({required this.shooter, required this.connectedness, required this.lastSeen});

  ConnectedShooter.copy(ConnectedShooter other) :
      this.shooter = other.shooter,
      this.connectedness = other.connectedness,
      this.lastSeen = other.lastSeen;
}

enum RatingMode {
  /// This rating system compares every shooter pairwise with every other shooter.
  /// [RatingSystem.updateShooterRatings]' scores parameter will contain two shooters
  /// to be compared.
  roundRobin,

  /// This rating system considers each shooter once per rating event, and does any
  /// additional iteration internally. [RatingSystem.updateShooterRatings]' scores
  /// parameter will contain scores for all shooters.
  oneShot,
}

abstract class RatingSystem {
  double get defaultRating;
  RatingMode get mode;

  /// Given some number of shooters (see [RatingMode]), update their ratings
  /// and return a map of the changes.
  ///
  /// [shooter] is the shooter or shooters whose ratings should change. If
  /// [mode] is [RatingMode.roundRobin], [shooters] is identical to the list
  /// of keys in [scores].
  ///
  /// [match] is the match and [stage] the stage in question. If [stage] is
  /// not null, the ratings are being done by stage.
  Map<ShooterRating, RatingChange> updateShooterRatings({required List<ShooterRating> shooters, required Map<ShooterRating, RelativeScore> scores, double matchStrengthMultiplier = 1.0, double connectednessMultiplier = 1.0});

  static const initialPlacementMultipliers = [
    // 1.5,
    // 1.5,
    // 1.5,
    // 1.5,
    // 1.5,
    // 1.5,
    // 1.5,
    // 1.5,
    // 1.5,
    // 1.5,
    2.5,
    2.25,
    2.0,
    1.75,
    1.625,
    1.5,
    1.4,
    1.3,
    1.2,
    1.1,
  ];

  static const initialClassRatings = {
    Classification.GM: 1300.0,
    Classification.M: 1200.0,
    Classification.A: 1100.0,
    Classification.B: 1000.0,
    Classification.C: 900.0,
    Classification.D: 800.0,
    Classification.U: 800.0,
    Classification.unknown: 800.0,
    null: 800.0,
  };
}