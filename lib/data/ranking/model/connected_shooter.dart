/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';

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

  @override
  String toString() {
    return "${shooter.getName()} => ${connectedness.round()}";
  }
}