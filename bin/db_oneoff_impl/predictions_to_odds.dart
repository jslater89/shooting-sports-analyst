/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math';

import 'package:collection/collection.dart';
import 'package:dart_console/src/console.dart';
import 'package:shooting_sports_analyst/console/repl.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/extensions/registrations.dart';
import 'package:shooting_sports_analyst/data/database/match/rating_project_database.dart';
import 'package:shooting_sports_analyst/data/match_cache/registration_cache.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/match_prediction.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/odds/prediction.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/odds/probability.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/odds/wager.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/uspsa.dart';
import 'package:shooting_sports_analyst/ui/rater/prediction/registration_parser.dart';
import 'package:shooting_sports_analyst/util.dart';

import 'base.dart';

class PredictionsToOddsCommand extends DbOneoffCommand {
  PredictionsToOddsCommand(super.db);

  @override
  Future<void> executor(Console console, List<MenuArgumentValue> arguments) async {
    await RegistrationCache().ready;
    await AnalystDatabase().ready;

    var project = await db.getRatingProjectByName("L2s Main");
    var openGroup = await project!.groupForDivision(uspsaOpen).unwrap();
    var dbKnownShooters = await project.getRatings(openGroup!).unwrap();
    var knownShooters = dbKnownShooters.map((dbShooter) => project.settings.algorithm.wrapDbRating(dbShooter)).toList();
    var registrationRes = await getRegistrations(uspsaSport, _registrationUrl, [uspsaOpen], knownShooters);
    if(registrationRes.isErr()) {
      console.print("Error getting registrations: ${registrationRes.unwrapErr().message}");
      return;
    }
    var registration = registrationRes.unwrap();

    for(var unknown in registration.unmatchedShooters) {
      var knownMapping = await db.getMatchRegistrationMappingByName(matchId: registration.matchId, shooterName: unknown.name, shooterDivisionName: unknown.division.name);
      if(knownMapping != null) {
        var foundMapping = knownShooters.firstWhereOrNull((s) => s.knownMemberNumbers.intersects(knownMapping.detectedMemberNumbers));
        if(foundMapping != null) {
          registration.registrations[unknown] = foundMapping;
        }
      }
    }
    var predictions = project.settings.algorithm.predict(registration.registrations.values.toList(), seed: 1234567890);

    Map<ShooterRating, AlgorithmPrediction> shootersToPredictions = {};
    for(var prediction in predictions) {
      shootersToPredictions[prediction.shooter] = prediction;
    }

    var christiansailer = knownShooters.firstWhereOrNull((s) => s.wrappedRating.deduplicatorName == "christiansailer");
    var mikehwang = knownShooters.firstWhereOrNull((s) => s.wrappedRating.deduplicatorName == "mikehwang");
    var bryanjones = knownShooters.firstWhereOrNull((s) => s.wrappedRating.deduplicatorName == "bryanjones");
    var aaroneddins = knownShooters.firstWhereOrNull((s) => s.wrappedRating.deduplicatorName == "aaroneddins");
    var russelldaniels = knownShooters.firstWhereOrNull((s) => s.wrappedRating.deduplicatorName == "russelldaniels");
    var gregoryclement = knownShooters.firstWhereOrNull((s) => s.wrappedRating.deduplicatorName == "gregoryclement");
    var johnvlieger = knownShooters.firstWhereOrNull((s) => s.wrappedRating.deduplicatorName == "johnvlieger");
    var chrisgelnett = knownShooters.firstWhereOrNull((s) => s.wrappedRating.deduplicatorName == "chrisgelnett");
    var bridgerhavens = knownShooters.firstWhereOrNull((s) => s.wrappedRating.deduplicatorName == "bridgerhavens");
    var robertkrogh = knownShooters.firstWhereOrNull((s) => s.wrappedRating.deduplicatorName == "robertkrogh");
    // var christilley = knownShooters.firstWhereOrNull((s) => s.wrappedRating.deduplicatorName == "christilley");
    var userPredictions = <UserPrediction>[
      UserPrediction(shooter: christiansailer!, bestPlace: 1, worstPlace: 3),
      UserPrediction(shooter: mikehwang!, bestPlace: 1, worstPlace: 4),
      UserPrediction(shooter: bryanjones!, bestPlace: 1, worstPlace: 5),
      UserPrediction(shooter: aaroneddins!, bestPlace: 1, worstPlace: 10),
      UserPrediction(shooter: russelldaniels!, bestPlace: 1, worstPlace: 10),
      UserPrediction(shooter: gregoryclement!, bestPlace: 1, worstPlace: 10),
      UserPrediction(shooter: johnvlieger!, bestPlace: 1, worstPlace: 10),
      UserPrediction(shooter: chrisgelnett!, bestPlace: 1, worstPlace: 10),
      UserPrediction(shooter: bridgerhavens!, bestPlace: 1, worstPlace: 10),
      UserPrediction(shooter: robertkrogh!, bestPlace: 1, worstPlace: 10),
      // UserPrediction(shooter: christilley!, bestPlace: 1, worstPlace: 10),
    ];

    // Generate odds for individual predictions
    var individualOdds = <UserPrediction, PredictionProbability>{};
    var random = Random(registration.matchId.stableHash);
    for (var userPred in userPredictions) {
      var shooterPrediction = shootersToPredictions[userPred.shooter];
      if (shooterPrediction == null) {
        console.print("Warning: No prediction found for ${userPred.shooter.getName()}");
        continue;
      }

      var probability = PredictionProbability.fromUserPrediction(
        userPred,
        shootersToPredictions,
        disasterChance: 0.01,
        random: random,
      );

      if (probability.probability < 0 || probability.probability > 1) {
        console.print("Warning: Invalid probability $probability for ${userPred.shooter.getName()}, skipping...");
        continue;
      }

      // Handle edge cases for very confident predictions
      if (probability == 0.0) {
        console.print("Warning: Zero probability for ${userPred.shooter.getName()} - prediction suggests impossible outcome");
        // continue;
      }
      if (probability == 1.0) {
        console.print("Warning: Certain probability for ${userPred.shooter.getName()} - prediction suggests guaranteed outcome");
        //continue;
      }

      individualOdds[userPred] = probability;
    }

    // Generate parlay odds using the individual odds and predictions
    // Use joint probability for likely scenarios, naive combination for unlikely ones
    var parlay = Parlay(
      legs: userPredictions.map((userPred) => Wager(prediction: userPred, probability: individualOdds[userPred]!, amount: 1.0)).toList(),
      amount: 1.0,
    );
    var parlayProbability = parlay.probability;

    // For debugging/comparison, also calculate joint probability
    // var jointProbability = _simulateParlay(console, userPredictions, individualOdds, shootersToPredictions);
    // console.print("Naive parlay probability: ${(parlayProbability * 100).toStringAsFixed(2)}%");
    // console.print("Joint parlay probability: ${(jointProbability * 100).toStringAsFixed(2)}%");

    bool parlayFailed = false;
    if (parlayProbability.probability < 0 || parlayProbability.probability > 1) {
      console.print("Warning: Invalid parlay probability $parlayProbability, skipping parlay odds...");
      parlayFailed = true;
    }

    if (parlayProbability.probability == 0.0) {
      console.print("Warning: Zero parlay probability - one or more predictions suggest impossible outcomes");
      parlayFailed = true;
    }
    if (parlayProbability.probability == 1.0) {
      console.print("Warning: Certain parlay probability - all predictions suggest guaranteed outcomes");
      parlayFailed = true;
    }

    // Display results
    console.print("\n=== Individual Prediction Odds ===");
    for (var entry in individualOdds.entries) {
      var userPred = entry.key;
      var predictionProb = entry.value;
      var probability = predictionProb.rawProbability;

      console.print("${userPred.shooter.getName()}: ${userPred.bestPlace}-${userPred.worstPlace} place");
      console.print("  Raw Probability: ${(probability * 100).toStringAsFixed(2)}%");
      console.print("  Probability w/ Edge: ${(predictionProb.probabilityWithHouseEdge * 100).toStringAsFixed(2)}%");
      console.print("  Decimal Odds: ${predictionProb.decimalOdds.toStringAsFixed(3)}");
      console.print("  Fractional Odds: ${predictionProb.fractionalOdds}");
      console.print("  Moneyline: ${predictionProb.moneylineOdds}");
      console.print("");
    }

    if(!parlayFailed) {

      console.print("=== Parlay Odds ===");
      console.print("All predictions combined:");
      console.print("  Validity Check: ${parlay.isPossible() ? "Valid" : "Possibly Invalid"}");
      console.print("  Specificity: ${(parlay.specificity * 100).toStringAsFixed(2)}%");
      console.print("  Fill: ${(parlay.fillProportion * 100).toStringAsFixed(2)}%");
      console.print("  Raw Probability: ${(parlayProbability.rawProbability * 100).toStringAsFixed(2)}%");
      console.print("  Probability w/ Edge: ${(parlayProbability.probabilityWithHouseEdge * 100).toStringAsFixed(2)}%");
      console.print("  Decimal Odds: ${parlayProbability.decimalOdds.toStringAsFixed(3)}");
      console.print("  Fractional Odds: ${parlayProbability.fractionalOdds}");
      console.print("  Moneyline: ${parlayProbability.moneylineOdds}");
    }
  }

  @override
  String get key => "PO";
  @override
  String get title => "Predictions To Odds";
}

const _registrationUrl = "https://practiscore.com/vortex-race-gun-nationals-presented-by-berry-bullets/squadding";
