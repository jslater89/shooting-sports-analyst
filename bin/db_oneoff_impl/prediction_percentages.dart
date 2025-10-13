/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:io';

import 'package:collection/collection.dart';
import 'package:dart_console/src/console.dart';
import 'package:shooting_sports_analyst/console/labeled_progress_bar.dart';
import 'package:shooting_sports_analyst/console/repl.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/extensions/registrations.dart';
import 'package:shooting_sports_analyst/data/database/match/rating_project_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/match.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/match_cache/registration_cache.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/match_prediction.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/uspsa.dart';
import 'package:shooting_sports_analyst/ui/rater/prediction/registration_parser.dart';
import 'package:shooting_sports_analyst/util.dart';

import 'base.dart';

class PredictionPercentagesCommand extends DbOneoffCommand {
  PredictionPercentagesCommand(super.db);

  @override
  Future<void> executor(Console console, List<MenuArgumentValue> arguments) async {
    await RegistrationCache().ready;
    await AnalystDatabase().ready;

    var project = await db.getRatingProjectByName("L2s Main");
    var openGroup = await project!.groupForDivision(uspsaOpen).unwrap();

    // var calibrationFactor = await getCalibrationFactor(project, openGroup!, project.matchPointers);

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
    predictions.sort((a, b) => b.ordinal.compareTo(a.ordinal));
    var byRating = predictions.sorted((a, b) => b.shooter.rating.compareTo(a.shooter.rating)).toList();

    var ratingDelta = byRating[0].shooter.rating - byRating[byRating.length - 1].shooter.rating;
    var estimatedMinimumPercentage = 95.8 + -0.0457 * ratingDelta;
    console.print("Estimated minimum percentage: ${estimatedMinimumPercentage}%");
    var ratioFloor = estimatedMinimumPercentage / 100;
    var ratioMultiplier = 1.0 - ratioFloor;
    var minimumRatingScore = byRating[byRating.length - 1].shiftedCenter;

    Map<ShooterRating, AlgorithmPrediction> shootersToPredictions = {};
    for(var prediction in predictions) {
      shootersToPredictions[prediction.shooter] = prediction;
    }

    double topScore = byRating[0].shiftedCenter - minimumRatingScore;
    console.print("Top 25");
    for(int i = 0; i < 25; i++) {
      var p = predictions[i];
      var topPercent = ((p.upperBox - minimumRatingScore) / topScore) * ratioMultiplier + ratioFloor;
      var bottomPercent = ((p.lowerBox - minimumRatingScore) / topScore) * ratioMultiplier + ratioFloor;
      console.print("${i + 1}. ${p.shooter.name} (${p.shooter.rating.round()}): ${bottomPercent.asPercentage(decimals: 2, includePercent: true)} - ${topPercent.asPercentage(decimals: 2, includePercent: true)}");
    }

    console.print("\nBottom 25");
    for(int i = predictions.length - 25; i < predictions.length; i++) {
      var p = predictions[i];
      var topPercent = ((p.upperBox - minimumRatingScore) / topScore) * ratioMultiplier + ratioFloor;
      var bottomPercent = ((p.lowerBox - minimumRatingScore) / topScore) * ratioMultiplier + ratioFloor;
      console.print("${p.shooter.name} (${p.shooter.rating.round()}): ${bottomPercent.asPercentage(decimals: 2, includePercent: true)} - ${topPercent.asPercentage(decimals: 2, includePercent: true)}");
    }
  }

  Future<double> getCalibrationFactor(DbRatingProject project, RatingGroup group, List<MatchPointer> matches) async {
    var progressBar = LabeledProgressBar(maxValue: matches.length, initialLabel: "Calculating calibration factor: ...");
    // A map of match pointers to
    //   a map of rating ratios (as a percentage of the top rating at the match) to finish percentages.
    Map<MatchPointer, Map<double, double>> ratingDeltasToPercentages = {};
    for(var ptr in matches) {
      progressBar.tick("Calculating calibration factor: ${ptr.name}");

      var dbMatch = await db.getMatchByAnySourceId(ptr.sourceIds);
      if(dbMatch == null) {
        continue;
      }

      List<DbMatchEntry> openEntries = dbMatch.shooters.where((entry) => entry.divisionName == uspsaOpen.name).toList();
      openEntries.sort((a, b) => b.precalculatedScore!.ratio.compareTo(a.precalculatedScore!.ratio));

      DbShooterRating? topRating;
      DbMatchEntry? topEntry;
      DbShooterRating? percentile75Rating;
      DbMatchEntry? percentile75Entry;
      DbShooterRating? percentile50Rating;
      DbMatchEntry? percentile50Entry;
      DbShooterRating? percentile25Rating;
      DbMatchEntry? percentile25Entry;
      int percentile25Index = (openEntries.length * 0.75).round();
      int percentile50Index = (openEntries.length * 0.5).round();
      int percentile75Index = (openEntries.length * 0.25).round();

      // Find the first entry with a rating at 100/75/50/25 percentile
      for(int i = 0; i < openEntries.length; i++) {
        var entry = openEntries[i];
        var rating = await db.maybeKnownShooterSync(project: project, group: group, memberNumber: entry.memberNumber);
        if(rating != null) {
          if(topRating == null) {
            topRating = rating;
            topEntry = entry;
            i = percentile75Index;
          }
        }
      }

      for(int i = percentile75Index; i < openEntries.length; i++) {
        var entry = openEntries[i];
        var rating = await db.maybeKnownShooterSync(project: project, group: group, memberNumber: entry.memberNumber);
        if(rating != null) {
          if(percentile75Rating == null) {
            percentile75Rating = rating;
            percentile75Entry = entry;
            i = percentile50Index;
          }
        }
      }
      for(int i = percentile50Index; i < openEntries.length; i++) {
        var entry = openEntries[i];
        var rating = await db.maybeKnownShooterSync(project: project, group: group, memberNumber: entry.memberNumber);
        if(rating != null) {
          if(percentile50Rating == null) {
            percentile50Rating = rating;
            percentile50Entry = entry;
            i = percentile25Index;
          }
        }
      }
      for(int i = percentile25Index; i < openEntries.length; i++) {
        var entry = openEntries[i];
        var rating = await db.maybeKnownShooterSync(project: project, group: group, memberNumber: entry.memberNumber);
        if(rating != null) {
          if(percentile25Rating == null) {
            percentile25Rating = rating;
            percentile25Entry = entry;
            break;
          }
        }
      }

      if(topRating == null) {
        continue;
      }

      Map<double, double> matchPercentages = {};
      var topRatingValue = topRating.rating;
      matchPercentages[0.0] = 1.0;

      if(percentile75Rating != null && percentile75Entry?.precalculatedScore != null) {
        var ratingFraction = topRatingValue - percentile75Rating.rating;
        matchPercentages[ratingFraction] = percentile75Entry!.precalculatedScore!.ratio;
      }
      if(percentile50Rating != null && percentile50Entry?.precalculatedScore != null) {
        var ratingFraction = topRatingValue - percentile50Rating.rating;
        matchPercentages[ratingFraction] = percentile50Entry!.precalculatedScore!.ratio;
      }
      if(percentile25Rating != null && percentile25Entry?.precalculatedScore != null) {
        var ratingFraction = topRatingValue - percentile25Rating.rating;
        matchPercentages[ratingFraction] = percentile25Entry!.precalculatedScore!.ratio;
      }

      ratingDeltasToPercentages[ptr] = matchPercentages;
    }
    progressBar.complete();
    List<String> csvLines = ["Match, Rating Delta, Percent Finish Ratio"];
    for(var entry in ratingDeltasToPercentages.entries) {
      for(var entry2 in entry.value.entries) {
        csvLines.add("\"${entry.key.name}\",${entry2.key.toStringAsFixed(4)},${entry2.value.toStringAsFixed(4)}");
      }
    }
    var csv = csvLines.join("\n");
    await File("calibration_factors.csv").writeAsString(csv);

    // TODO: figure out the calibration factor
    return 1.0;
  }

  @override
  String get key => "PP";
  @override
  String get title => "Predictions To Percentages";
}

const _registrationUrl = "https://practiscore.com/vortex-race-gun-nationals-presented-by-berry-bullets/squadding";
