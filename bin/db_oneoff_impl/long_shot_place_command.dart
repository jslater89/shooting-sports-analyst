/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "dart:math";

import "package:collection/collection.dart";
import "package:dart_console/src/console.dart";
import "package:shooting_sports_analyst/console/repl.dart";
import "package:shooting_sports_analyst/data/database/match/rating_project_database.dart";
import "package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart";
import "package:shooting_sports_analyst/data/ranking/prediction/match_prediction.dart";
import "package:shooting_sports_analyst/data/ranking/prediction/odds/prediction.dart";
import "package:shooting_sports_analyst/data/ranking/prediction/odds/probability.dart";
import "package:shooting_sports_analyst/data/sport/builtins/uspsa.dart";

import "base.dart";

/// Target American moneyline for "long shot" (e.g. +10000 = 100:1).
const int _longShotMoneyline = 20000;

/// Decimal odds equivalent: win 10000 on 100 bet -> decimal 101.
const double _longShotDecimalOdds = _longShotMoneyline / 100.0 + 1.0;

/// One-off: build a synthetic "match" from top N competitors in a division
/// (e.g. top 100 Carry Optics in L2s Main), run predictions, generate win
/// odds for each place, and report at which place the win odds first reach
/// +10000 (or another threshold). No FutureMatch or MatchPrep is persisted.
class LongShotPlaceCommand extends DbOneoffCommand {
  LongShotPlaceCommand(super.db);

  @override
  Future<void> executor(Console console, List<MenuArgumentValue> arguments) async {
    var project = await db.getRatingProjectByName("L2s Main");
    if (project == null) {
      console.print("Rating project 'L2s Main Glicko' not found.");
      return;
    }

    var groupRes = await project.groupForDivision(uspsaCarryOptics);
    if (groupRes.isErr()) {
      console.print("Failed to get Carry Optics group: ${groupRes.unwrapErr()}");
      return;
    }
    var group = groupRes.unwrap();
    if (group == null) {
      console.print("No group for Carry Optics in this project.");
      return;
    }

    var ratingsRes = await project.getRatings(group);
    if (ratingsRes.isErr()) {
      console.print("Failed to get ratings: ${ratingsRes.unwrapErr()}");
      return;
    }
    var dbRatings = ratingsRes.unwrap();
    var sorted = dbRatings.where((r) => r.lastSeen.isAfter(DateTime(2024, 1, 1))).sorted((a, b) => b.rating.compareTo(a.rating));
    const topN = 400;
    var take = sorted.take(topN).toList();
    if (take.isEmpty) {
      console.print("No ratings in Carry Optics.");
      return;
    }

    var wrapped = take.map((r) => project.settings.algorithm.wrapDbRating(r)).toList();
    var seed = DateTime.now().millisecondsSinceEpoch;
    var predictions = project.settings.algorithm.predict(wrapped, seed: seed);
    Map<ShooterRating, AlgorithmPrediction> shootersToPredictions = {};
    for (var p in predictions) {
      shootersToPredictions[p.shooter] = p;
    }

    // Order by predicted strength (mean descending) so place 1 = favorite, place N = Nth favorite.
    var byMean = predictions.sorted((a, b) => b.displayCenter.compareTo(a.displayCenter));
    var random = Random(seed);

    console.print("Top $topN Carry Optics (L2s Main Glicko) by rating; win odds by predicted place.");
    console.print("Finding first place where win odds >= +$_longShotMoneyline (decimal ${_longShotDecimalOdds.toStringAsFixed(1)}).\n");

    int? firstLongShotPlace;
    const window = 3;
    int trials = 25000;
    for (var place = 1; place <= byMean.length; place++) {
      var pred = byMean[place - 1];
      var placePred = PlacePrediction(shooter: pred.shooter, bestPlace: 1, worstPlace: 1);
      var prob = PredictionProbability.fromPlacePrediction(
        placePred,
        shootersToPredictions,
        random: random,
        disasterChance: 0.01,
        trials: trials,
      );
      var decimal = prob.decimalOdds;
      var moneyline = prob.moneylineOdds;
      final longShot = firstLongShotPlace;
      if (longShot == null && decimal >= _longShotDecimalOdds) {
        firstLongShotPlace = place;
      }
      final current = firstLongShotPlace;
      var mark = (current == place) ? " <-- +$_longShotMoneyline long shot" : "";
      if (place <= 10 || place >= byMean.length - 5 || (current != null && place >= current - window && place <= current + window)) {
        console.print("Place $place: ${pred.shooter.getName()}  Win odds: $moneyline (decimal ${decimal.toStringAsFixed(2)})$mark");
      }
      else if (place == 11) {
        console.print("...");
      }
      else if (firstLongShotPlace != null && place >= firstLongShotPlace + window) {
        break;
      }
    }

    final longShotPlace = firstLongShotPlace;
    if (longShotPlace != null) {
      console.print("\nFirst place that is a +$_longShotMoneyline long shot to win: Place $longShotPlace (${byMean[longShotPlace - 1].shooter.getName()}).");
    }
    else {
      console.print("\nNo place in the top $topN reaches +$_longShotMoneyline win odds; highest place checked was ${byMean.length}.");
    }
  }

  @override
  String get key => "LSP";
  @override
  String get title => "Long-shot place (CO +$_longShotMoneyline)";
}
