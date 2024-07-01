/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */


/*
It seems like the right choice, on reading about it a little. We do actually have several
functions we're evaluating on, even if they aren't yet explicit:

1. Minimize Elo error (expected/actual score).
2. Make good *ordinal* predictions for the top 10-15% of shooters at a match. I don't
think I can do percentage predictions because those are so loosey-goosey hand-tuned.
3. Have the average rating be close to 1000. I think this is a freebie, though.
4. Have the Sailer/Nils/JJ/Hetherington ratings be between 2000 and 3000, with the
most points for coming in around 2700.
5. Make good ordinal predictions all the way down the list.
6? Minimize rating errors at the terminal end of calibration.

I may think of others, but this is a pretty good set to start with.
 */

import 'dart:math';

import 'package:collection/collection.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/ranking/evolution/predator_prey.dart';
import 'package:shooting_sports_analyst/data/ranking/project_manager.dart';
import 'package:shooting_sports_analyst/data/ranking/rater.dart';
import 'package:shooting_sports_analyst/data/ranking/rater_types.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/elo/elo_rater_settings.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/elo/elo_shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/elo/multiplayer_percent_elo_rater.dart';
import 'package:shooting_sports_analyst/data/ranking/rating_history.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/uspsa.dart';
import 'package:shooting_sports_analyst/data/sport/model.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/scoring.dart';

class EloEvaluator extends Prey<EloEvaluator> {
  int generation;

  /// The settings used for this iteration.
  EloSettings settings;

  /// The calculated errors for each set of predictions.
  Map<String, double> errors = {};

  /// The total error across all predictions in the training
  /// set, which is the quantity we want to minimize.
  double get totalError => errors.values.sum;

  /// The average rating output.
  Map<String, double> averageRatings = {};
  double get averageRating => averageRatings.values.average;

  Map<String, double> averageRatingErrors = {};
  double get averageRatingError => averageRatingErrors.values.average;

  /// The average maximum rating.
  Map<String, double> maxRatingDiffs = {};
  double get averageMaxRatingDiff => maxRatingDiffs.values.average;

  Map<String, int> topNOrdinalErrors = {};
  int get totalTopNOrdinalError => topNOrdinalErrors.values.sum;

  EloEvaluator({
    required this.generation,
    required this.settings,
  });

  Future<double> evaluate(EloEvaluationData data, [Future<void> Function(int, int)? callback]) async {
    int lastProgress = 0;
    var h = RatingHistory(
      sport: uspsaSport,
      verbose: false,
      matches: [],
      ongoingMatches: [],
      project: DbRatingProject(
        sportName: "USPSA",
          name: "Evolutionary test",
          settings: RatingProjectSettings(
            algorithm: MultiplayerPercentEloRater(settings: settings),
          )
      ),
      progressCallback: (current, total, name) async {
        lastProgress = current;
        await callback?.call(current, total);
      },
    );

    await h.processInitialMatches();

    // TODO: make it JsonSerializable?
    // h = await Isolate.run<RatingHistory>(() async {
    //   await h.processInitialMatches();
    //   return h;
    // });

    var rater = h.raterFor(h.matches.last, data.group);
    var sorted = rater.knownShooters.values.sorted((a, b) => b.rating.compareTo(a.rating));
    averageRatings[data.name] = sorted.map((r) => r.rating).average;
    maxRatingDiffs[data.name] = (data.expectedMaxRating - sorted.first.rating).abs();
    averageRatingErrors[data.name] = sorted.map((r) => (r as EloShooterRating).meanSquaredErrorWithWindow()).average;

    lastProgress += 1;
    for(var m in data.evaluationData) {
      await callback?.call(lastProgress++, data.evaluationData.length);
      int ordinalErrors = 0;
      Map<MatchEntry, ShooterRating> registrations = {};
      for(var shooter in m.shooters) {
        var rating = rater.knownShooters[Rater.processMemberNumber(shooter.memberNumber)];
        if(rating != null) registrations[shooter] = rating;
      }

      int topN = max(1, (registrations.length * 0.15).round());

      var predictions = rater.ratingSystem.predict(registrations.values.toList());
      var scoreOutput = m.getScores(shooters: registrations.keys.toList());

      var scores = <ShooterRating, RelativeMatchScore>{};
      for(var s in scoreOutput.values) {
        var rating = registrations[s.shooter];
        if(rating != null) scores[rating] = s;
      }

      var evaluations = rater.ratingSystem.validate(
        shooters: registrations.values.toList(),
        scores: scores.map((k, v) => MapEntry(k, v)),
        matchScores: scores,
        predictions: predictions,
        chatty: false,
      );

      var ordinalSorted = evaluations.actualResults.keys.sorted((a, b) => b.ordinal.compareTo(a.ordinal));
      if(ordinalSorted.length > 0) {
        for (int i = 1; i <= topN; i++) {
          ordinalErrors += (i - (evaluations.actualResults[ordinalSorted[i - 1]]!.place)).abs();
        }
      }

      // I think unnormalizing here is right because it'll help stop the 'best system rates
      // everyone equally and is thus never that wrong' problem.
      errors[data.name] = evaluations.error * predictions.length;

      topNOrdinalErrors[data.name] = ordinalErrors;
    }

    return totalError;
  }

  bool get evaluated => evaluations.isNotEmpty;

  Map<EloEvalFunction, double> evaluations = {};
  static Map<String, EloEvalFunction> evaluationFunctions = {
    "totErr": (e) {
      return e.totalError;
    },
    "maxRat": (e) {
      // I think this is valid: the best people in a dataset of about 200-300
      // matches should end up at about 2700.
      return e.averageMaxRatingDiff;
    },
    "avgRat": (e) {
      return (1000 - e.averageRating).abs();
    },
    "ord": (e) {
      return e.totalTopNOrdinalError.toDouble();
    },
    "avgErr": (e) {
      return e.averageRatingError;
    }
  };

  @override
  String toString() {
    return "EloEvaluator $generation.$hashCode";
  }
}

typedef EloEvalFunction = double Function(EloEvaluator);

class EloEvaluationData {
  final String name;
  final List<ShootingMatch> trainingData;
  final List<ShootingMatch> evaluationData;
  final DbRatingGroup group;
  final double expectedMaxRating;

  EloEvaluationData({required this.name, required this.trainingData, required this.evaluationData, required this.group, required this.expectedMaxRating});

  int get totalSteps {
    return trainingData.map((m) => m.stages.length).sum;
  }
}
