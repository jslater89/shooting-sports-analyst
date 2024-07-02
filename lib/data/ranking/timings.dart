/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

class Timings {
  static const enabled = false;

  static Timings? _instance;

  factory Timings() {
    if(_instance == null) _instance = Timings._();
    return _instance!;
  }

  Timings._();

  void reset() {
    addShootersMillis = 0.0;
    shooterCount = 0;
    dedupShootersMillis = 0.0;
    rateMatchesMillis = 0.0;
    matchCount = 0;
    getShootersAndScoresMillis = 0.0;
    matchStrengthMillis = 0.0;
    connectednessModMillis = 0.0;
    rateShootersMillis = 0.0;
    pubstompMillis = 0.0;
    scoreMapMillis = 0.0;
    calcExpectedScore = 0.0;
    updateRatings = 0.0;
    printInfo = 0.0;
    updateMillis = 0.0;
    updateConnectednessMillis = 0.0;
    removeUnseenShootersMillis = 0.0;
  }

  double addShootersMillis = 0.0;
  int shooterCount = 0;

  double dedupShootersMillis = 0.0;
  
  // Begin match rating
  double rateMatchesMillis = 0.0;
  int matchCount = 0;
  double getShootersAndScoresMillis = 0.0;
  double matchStrengthMillis = 0.0;
  double connectednessModMillis = 0.0;
  double rateShootersMillis = 0.0;

  // Begin oneshot timings
  double pubstompMillis = 0.0;
  double scoreMapMillis = 0.0;

  // Begin Elo timings
  double calcExpectedScore = 0.0;
  double updateRatings = 0.0;
  double printInfo = 0.0;
  // End Elo timings

  double updateMillis = 0.0;
  // End oneshot timings

  double updateConnectednessMillis = 0.0;
  // End match rating

  double removeUnseenShootersMillis = 0.0;

  double get sum => addShootersMillis + dedupShootersMillis + rateMatchesMillis + removeUnseenShootersMillis;

  @override
  String toString() {
    var content = "TIMINGS:\n";
    content += "Add shooters: ${addShootersMillis.toStringAsFixed(1)} for $shooterCount shooters\n";
    content += "Dedup shooters: ${dedupShootersMillis.toStringAsFixed(1)}\n";
    content += "Rate matches: ${rateMatchesMillis.toStringAsFixed(1)} for $matchCount matches\n";
    content += "\tGet shooters/scores: ${getShootersAndScoresMillis.toStringAsFixed(1)}\n";
    content += "\tCalc match strength: ${matchStrengthMillis.toStringAsFixed(1)}\n";
    content += "\tCalc connectedness: ${connectednessModMillis.toStringAsFixed(1)}\n";
    content += "\tRate shooters: ${rateShootersMillis.toStringAsFixed(1)}\n";
    content += "\t\tPubstomp: ${pubstompMillis.toStringAsFixed(1)}\n";
    content += "\t\tScore map: ${scoreMapMillis.toStringAsFixed(1)}\n";
    content += "\t\tUpdate: ${updateMillis.toStringAsFixed(1)}\n";
    content += "\t\t\tCalc expected: ${calcExpectedScore.toStringAsFixed(1)}\n";
    content += "\t\t\tUpdate ratings: ${updateRatings.toStringAsFixed(1)}\n";
    content += "\t\t\tPrint info: ${printInfo.toStringAsFixed(1)}\n";
    content += "\tUpdate connectedness: ${updateConnectednessMillis.toStringAsFixed(1)}\n";
    content += "Remove unseen shooters: ${removeUnseenShootersMillis.toStringAsFixed(1)}\n";
    content += "Total: ${sum.toStringAsFixed(1)}, ${(sum / (shooterCount * matchCount)).toStringAsFixed(3)} per match entry";

    return content;
  }
}