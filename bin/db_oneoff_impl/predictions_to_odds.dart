import 'package:collection/collection.dart';
import 'package:dart_console/src/console.dart';
import 'dart:math';

import 'package:shooting_sports_analyst/console/repl.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/extensions/registrations.dart';
import 'package:shooting_sports_analyst/data/database/match/rating_project_database.dart';
import 'package:shooting_sports_analyst/data/match_cache/registration_cache.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/match_prediction.dart';
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

    Map<ShooterRating, ShooterPrediction> shootersToPredictions = {};
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
      UserPrediction(shooter: christiansailer!, bestPlace: 1, worstPlace: 10),
      UserPrediction(shooter: mikehwang!, bestPlace: 1, worstPlace: 10),
      UserPrediction(shooter: bryanjones!, bestPlace: 1, worstPlace: 10),
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
    var individualOdds = <UserPrediction, DecimalOdds>{};
    var random = Random(registration.matchId.stableHash);
    for (var userPred in userPredictions) {
      var shooterPrediction = shootersToPredictions[userPred.shooter];
      if (shooterPrediction == null) {
        console.print("Warning: No prediction found for ${userPred.shooter.getName()}");
        continue;
      }

      var probability = _calculatePlaceRangeProbability(
        console,
        shooterPrediction,
        userPred.bestPlace,
        userPred.worstPlace,
        shootersToPredictions,
        random: random
      );

      if (probability < 0 || probability > 1) {
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

      individualOdds[userPred] = DecimalOdds.fromProbability(probability, houseEdge: 0.05);
    }

    // Generate parlay odds using the individual odds and predictions
    // Use joint probability for likely scenarios, naive combination for unlikely ones
    var parlayProbability = _combineOddsParlay(console, userPredictions, individualOdds);

    // For debugging/comparison, also calculate joint probability
    // var jointProbability = _simulateParlay(console, userPredictions, individualOdds, shootersToPredictions);
    // console.print("Naive parlay probability: ${(parlayProbability * 100).toStringAsFixed(2)}%");
    // console.print("Joint parlay probability: ${(jointProbability * 100).toStringAsFixed(2)}%");

    bool parlayFailed = false;
    if (parlayProbability < 0 || parlayProbability > 1) {
      console.print("Warning: Invalid parlay probability $parlayProbability, skipping parlay odds...");
      parlayFailed = true;
    }

    if (parlayProbability == 0.0) {
      console.print("Warning: Zero parlay probability - one or more predictions suggest impossible outcomes");
      parlayFailed = true;
    }
    if (parlayProbability == 1.0) {
      console.print("Warning: Certain parlay probability - all predictions suggest guaranteed outcomes");
      parlayFailed = true;
    }

    // Display results
    console.print("\n=== Individual Prediction Odds ===");
    for (var entry in individualOdds.entries) {
      var userPred = entry.key;
      var odds = entry.value;
      var probability = odds.toProbability();

      console.print("${userPred.shooter.getName()}: ${userPred.bestPlace}-${userPred.worstPlace} place");
      console.print("  Raw Probability: ${(probability * 100).toStringAsFixed(2)}%");
      console.print("  Probability w/ Edge: ${(odds.toProbabilityWithHouseEdge() * 100).toStringAsFixed(2)}%");
      console.print("  Decimal Odds: ${odds.decimal.toStringAsFixed(2)}");
      console.print("  Fractional Odds: ${odds.fractional}");
      console.print("  Moneyline: ${odds.moneyline}");
      console.print("");
    }

    if(!parlayFailed) {
      var parlayOdds = DecimalOdds.fromProbability(parlayProbability, houseEdge: 0.09);

      console.print("=== Parlay Odds ===");
      console.print("All predictions combined:");
      console.print("  Raw Probability: ${(parlayProbability * 100).toStringAsFixed(2)}%");
      console.print("  Probability w/ Edge: ${(parlayOdds.toProbabilityWithHouseEdge() * 100).toStringAsFixed(2)}%");
      console.print("  Decimal Odds: ${parlayOdds.decimal.toStringAsFixed(2)}");
      console.print("  Fractional Odds: ${parlayOdds.fractional}");
      console.print("  Moneyline: ${parlayOdds.moneyline}");
    }
  }

  /// Calculate the probability that a shooter finishes within the specified place range
  double _calculatePlaceRangeProbability(
    Console console,
    ShooterPrediction shooterPrediction,
    int bestPlace,
    int worstPlace,
    Map<ShooterRating, ShooterPrediction> shooterToPrediction,
    {
      Random? random,
    }
  ) {
    // Use Monte Carlo simulation with the actual prediction data
    // mean = average expected score from 1000 Monte Carlo runs
    // oneSigma = standard deviation of those runs
    // ciOffset = trend shift (-0.9 to 0.9)

    var trials = 10000;
    var successes = 0;

    var actualRandom = random ?? Random();

    for (var i = 0; i < trials; i++) {
      // Generate a random expected score for this shooter
      var z = actualRandom.nextGaussian();
      var shooterExpectedScore = shooterPrediction.mean + shooterPrediction.oneSigma * z;

      // Apply trend shift
      shooterExpectedScore += shooterPrediction.ciOffset * (shooterPrediction.oneSigma / 2);

      // Generate random expected scores for all other shooters
      var otherExpectedScores = <double>[];
      for (var otherPred in shooterToPrediction.values) {
        if (otherPred == shooterPrediction) continue;

        var otherZ = actualRandom.nextGaussian();
        var otherExpectedScore = otherPred.mean + otherPred.oneSigma * otherZ;
        otherExpectedScore += otherPred.ciOffset * otherPred.oneSigma;

        otherExpectedScores.add(otherExpectedScore);
      }

      // Count how many shooters have higher expected scores (higher score = better placement)
      var betterCount = otherExpectedScores.where((score) => score > shooterExpectedScore).length;
      var place = betterCount + 1;

      if (place >= bestPlace && place <= worstPlace) {
        successes++;
      }
    }

    var minProbability = 1 / trials;
    var maxProbability = (successes - 1) / trials;
    var probability = (successes / trials).clamp(minProbability, maxProbability);

    return probability;
  }


  /// Calculate the probability that all user predictions are correct (parlay)
  /// using naive independent combination (fast but less accurate)
  double _combineOddsParlay(
    Console console,
    List<UserPrediction> userPredictions,
    Map<UserPrediction, DecimalOdds> individualOdds,
  ) {

    if(!_isParlayPossible(userPredictions)) {
      console.print("Warning: Parlay is impossible due to overlapping place ranges");
      return 0.0;
    }

    // For a parlay, we need the probability that ALL predictions are correct
    // This is the product of individual probabilities, assuming independence
    var parlayProbability = 1.0;

    for (var userPred in userPredictions) {
      var odds = individualOdds[userPred];
      if (odds == null) {
        console.print("Warning: No odds found for ${userPred.shooter.getName()}, skipping from parlay");
        continue;
      }

      var individualProbability = odds.toProbability();
      parlayProbability *= individualProbability;
    }

    var fullness = _parlayFillProportion(userPredictions);
    var legCount = userPredictions.length;

    // For parlays more than 75% full, decrease the probability by between 0% and 25%.
    // Probability is our estimate that the parlay is correct, so we decrease it to make
    // the payout higher.
    if(fullness > 0.75) {
      parlayProbability *= (1 - (0.25 * (fullness - 0.75)));
    }
    // For parlays less than 50% full, increase the probability by between 0% and 25%.
    // This reduces the payout for easy parlays.
    else if(fullness < 0.50) {
      parlayProbability *= (1 + (0.25 * (0.50 - fullness)));
    }

    // For parlays with more than 5 legs, decrease the probability by 2% per leg, capped
    // at 10 legs.
    if(legCount > 5) {
      parlayProbability *= (1 - (0.02 * (min(legCount, 10) - 5)));
    }

    return parlayProbability;
  }

  // /// Calculate the probability that all user predictions are correct (parlay)
  // /// using joint probability simulation to account for correlations
  // double _simulateParlay(
  //   Console console,
  //   List<UserPrediction> userPredictions,
  //   Map<UserPrediction, DecimalOdds> individualOdds,
  //   Map<ShooterRating, ShooterPrediction> shootersToPredictions,
  //   {int seed = 1234567890}
  // ) {
  //   // First, check for impossible combinations due to overlapping ranges
  //   if (!_isParlayPossible(userPredictions)) {
  //     console.print("Warning: Parlay is impossible due to overlapping place ranges");
  //     return 0.0;
  //   }

  //   // Use Monte Carlo simulation to account for correlations between shooter performances
  //   // This generates complete rankings and checks if all parlay predictions are satisfied
  //   var trials = 100000;
  //   var successes = 0;

  //   Random? random;
  //   if(seed != null) {
  //     random = Random(seed);
  //   }

  //   for (var i = 0; i < trials; i++) {
  //     // Generate a complete ranking for all shooters using their prediction data
  //     var ranking = _generateCompleteRankingFromPredictions(shootersToPredictions, random: random);

  //     // Check if all parlay predictions are satisfied in this ranking
  //     bool allPredictionsSatisfied = true;

  //     for (var userPred in userPredictions) {
  //       var shooterPlace = ranking[userPred.shooter]!;

  //       if (shooterPlace < userPred.bestPlace || shooterPlace > userPred.worstPlace) {
  //         allPredictionsSatisfied = false;
  //         break;
  //       }
  //     }

  //     if (allPredictionsSatisfied) {
  //       successes++;
  //     }
  //   }

  //   return successes / trials;
  // }

  /// Check if a parlay is logically possible given the place ranges
  bool _isParlayPossible(List<UserPrediction> userPredictions) {
    // Calculate the number of predictions that cover each place.
    Map<int, int> requiredAtPlace = {};
    for(var pred in userPredictions) {
      for(var place = pred.bestPlace; place <= pred.worstPlace; place++) {
        requiredAtPlace.increment(place);
      }
    }

    // For each prediction
    for(var pred in userPredictions) {
      var range = pred.worstPlace - pred.bestPlace + 1;
      // If any place in this prediction is required more than the range of this prediction,
      // the parlay is impossible.
      for(var place = pred.bestPlace; place <= pred.worstPlace; place++) {
        if(requiredAtPlace[place]! > range) {
          return false;
        }
      }
    }
    return true;
  }

  /// Return a factor from 0 to 1 representing how 'full' the parlay is.
  ///
  /// A "full parlay" is one where each place covered by the parlay must be
  /// occupied by a prediction, e.g. a 10-leg parlay where each leg predicts
  /// a top 10 finish.
  ///
  /// Impossible parlays will have values greater than 1.
  double _parlayFillProportion(List<UserPrediction> userPredictions) {
    // Calculate the number of predictions that cover each place.
    Map<int, int> requiredAtPlace = {};
    for(var pred in userPredictions) {
      for(var place = pred.bestPlace; place <= pred.worstPlace; place++) {
        requiredAtPlace.increment(place);
      }
    }

    // Calculate the fill proportion for each prediction.
    List<double> predictionProportions = [];
    for(var pred in userPredictions) {
      var range = pred.worstPlace - pred.bestPlace + 1;
      // If any place in this prediction is required more than the range of this prediction,
      // the parlay is impossible.
      List<double> proportions = [];
      for(var place = pred.bestPlace; place <= pred.worstPlace; place++) {
        proportions.add(requiredAtPlace[place]! / range);
      }
      predictionProportions.add(proportions.average);
    }
    return predictionProportions.average;
  }

  /// Generate a complete ranking for all shooters using their individual prediction data
  Map<ShooterRating, int> _generateCompleteRankingFromPredictions(
    Map<ShooterRating, ShooterPrediction> shootersToPredictions,
    {Random? random}
  ) {
    var shooterScores = <ShooterRating, double>{};
    var actualRandom = random ?? Random();
    var shooters = shootersToPredictions.keys.toList();
    var seenShooters = <ShooterRating>[];

    for (var shooter in shooters) {
      // Find the ShooterPrediction for this shooter
      var shooterPrediction = shootersToPredictions[shooter];

      if (shooterPrediction != null) {
        // Generate a random expected score using the prediction's mean, sigma, and trendShift
        var z = actualRandom.nextGaussian();
        var expectedScore = shooterPrediction.mean + shooterPrediction.oneSigma * z;

        // Apply trend shift
        expectedScore += shooterPrediction.ciOffset * shooterPrediction.oneSigma;

        shooterScores[shooter] = expectedScore;
        seenShooters.add(shooter);
      }
    }

    // Sort shooters by their expected scores (higher score = better placement)
    var sortedShooters = seenShooters
      ..sort((a, b) => shooterScores[b]!.compareTo(shooterScores[a]!));

    // Assign places based on ranking
    var ranking = <ShooterRating, int>{};
    for (var i = 0; i < sortedShooters.length; i++) {
      ranking[sortedShooters[i]] = i + 1;
    }

    return ranking;
  }

  @override
  String get key => "PO";
  @override
  String get title => "Predictions To Odds";
}

const _registrationUrl = "https://practiscore.com/vortex-race-gun-nationals-presented-by-berry-bullets/squadding";

/// A prediction from a user for a shooter's finish.
class UserPrediction {
  final ShooterRating shooter;
  final int bestPlace;
  final int worstPlace;

  UserPrediction({
    required this.shooter,
    required this.bestPlace,
    required this.worstPlace,
  }) {
    if (bestPlace > worstPlace) {
      throw ArgumentError("Best place must be less than worst place");
    }
  }

  UserPrediction.exactPlace(this.shooter, this.bestPlace) : this.worstPlace = bestPlace;
}

/// Represents decimal odds for betting.
class DecimalOdds {
  static const worstPossibleOdds = 1.0001;

  /// The raw decimal odds, before the house edge is applied.
  final double rawDecimal;

  /// The decimal odds, after the house edge is applied.
  ///
  /// House edge reduces the payout.
  double get decimal => max(worstPossibleOdds, rawDecimal * (1 - houseEdge));

  /// The house edge, as a percentage.
  ///
  /// House edge reduces the payout.
  final double houseEdge;

  DecimalOdds(this.rawDecimal, {this.houseEdge = 0.00}) {
    if (rawDecimal <= 1.0) {
      throw ArgumentError("Decimal odds must be greater than 1.0");
    }
  }

  factory DecimalOdds.fromProbability(double probability, {double houseEdge = 0.00}) {
    if (probability <= 0 || probability >= 1) {
      throw ArgumentError("Probability must be between 0 and 1");
    }
    return DecimalOdds(1.0 / probability, houseEdge: houseEdge);
  }

  double toProbability() => 1.0 / rawDecimal;
  double toProbabilityWithHouseEdge() => 1.0 / decimal;

  String get fractional {
    var numerator = decimal - 1.0;
    // var denominator = 1.0;

    // Convert to fractional odds (e.g., 2.5 -> 3/2)
    // Find the simplest fraction representation
    var gcd = _gcd((numerator * 100).round(), 100);
    var num = (numerator * 100).round() ~/ gcd;
    var den = 100 ~/ gcd;

    return "$num/$den";
  }

  String get moneyline {
    if(decimal == 2.0) {
      return "+100";
    }
    else if (decimal > 2.0) {
      // Positive moneyline for underdogs
      var payout = (decimal - 1.0) * 100;
      return "+${payout.round()}";
    } else {
      // Negative moneyline for favorites
      var stake = -100 / (decimal - 1.0);
      return "${stake.round()}";
    }
  }

  int _gcd(int a, int b) {
    while (b != 0) {
      var temp = b;
      b = a % b;
      a = temp;
    }
    return a;
  }
}

// Extension to add Gaussian random number generation
extension RandomGaussian on Random {
  double nextGaussian() {
    // Box-Muller transform
    var u1 = nextDouble();
    var u2 = nextDouble();
    return sqrt(-2 * log(u1)) * cos(2 * pi * u2);
  }
}
