import 'dart:isolate';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/ranking/evolution/genome.dart';
import 'package:uspsa_result_viewer/data/ranking/evolution/predator_prey.dart';
import 'package:uspsa_result_viewer/data/ranking/model/shooter_rating.dart';
import 'package:uspsa_result_viewer/data/ranking/project_manager.dart';
import 'package:uspsa_result_viewer/data/ranking/rater.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/elo/elo_rater_settings.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/elo/elo_shooter_rating.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/elo/multiplayer_percent_elo_rater.dart';
import 'package:uspsa_result_viewer/data/ranking/rating_history.dart';
import 'dart:math' as math;

var _r = math.Random();

// TODO: multi-objective predator-prey
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

class EloEvaluator extends Prey<EloEvaluator> {
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
    required this.settings,
  });

  Future<double> evaluate(EloEvaluationData data, [Future<void> Function(int, int)? callback]) async {
    var h = RatingHistory(
      verbose: false,
      matches: data.trainingData,
      project: RatingProject(
          name: "Evolutionary test",
          matchUrls: data.trainingData.map((e) => e.practiscoreId).toList(),
          settings: RatingHistorySettings(
            algorithm: MultiplayerPercentEloRater(settings: settings),
            groups: [data.group],
          )
      ),
      progressCallback: (current, total, name) async {
        await callback?.call(current, total);
      },
    );

    print("Processing matches");

    await h.processInitialMatches();

    // TODO: make it JsonSerializable?
    // h = await Isolate.run<RatingHistory>(() async {
    //   await h.processInitialMatches();
    //   return h;
    // });
    print("Matches processed");

    var rater = h.raterFor(h.matches.last, data.group);
    var sorted = rater.knownShooters.values.sorted((a, b) => b.rating.compareTo(a.rating));
    averageRatings[data.name] = sorted.map((r) => r.rating).average;
    maxRatingDiffs[data.name] = (data.expectedMaxRating - sorted.first.rating).abs();
    averageRatingErrors[data.name] = sorted.map((r) => (r as EloShooterRating).standardError).average;

    print("Predicting matches and validating predictions");
    for(var m in data.evaluationData) {
      int ordinalErrors = 0;
      Map<Shooter, ShooterRating> registrations = {};
      for(var shooter in m.shooters) {
        var rating = rater.knownShooters[Rater.processMemberNumber(shooter.memberNumber)];
        if(rating != null) registrations[shooter] = rating;
      }

      int topN = max(1, (registrations.length * 0.15).round());

      var predictions = rater.ratingSystem.predict(registrations.values.toList());
      var scoreOutput = m.getScores(shooters: registrations.keys.toList());

      var scores = <ShooterRating, RelativeScore>{};
      for(var s in scoreOutput) {
        var rating = registrations[s.shooter];
        if(rating != null) scores[rating] = s.total;
      }

      var evaluations = rater.ratingSystem.validate(
        shooters: registrations.values.toList(),
        scores: scores,
        matchScores: scores,
        predictions: predictions,
        chatty: false,
      );

      var ordinalSorted = evaluations.actualResults.keys.sorted((a, b) => b.ordinal.compareTo(a.ordinal));
      for(int i = 1; i <= topN; i++) {
        ordinalErrors += (i - (evaluations.actualResults[ordinalSorted[i]]!.place)).abs();
      }

      // I think unnormalizing here is right because it'll help stop the 'best system rates
      // everyone equally and is thus never that wrong' problem.
      errors[data.name] = evaluations.error * predictions.length;

      topNOrdinalErrors[data.name] = ordinalErrors;
    }
    print("Validation done");

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
    return "EloEvaluator $hashCode";
  }
}

typedef EloEvalFunction = double Function(EloEvaluator);

class EloEvaluationData {
  final String name;
  final List<PracticalMatch> trainingData;
  final List<PracticalMatch> evaluationData;
  final RaterGroup group;
  final double expectedMaxRating;

  EloEvaluationData({required this.name, required this.trainingData, required this.evaluationData, required this.group, required this.expectedMaxRating});

  int get totalSteps {
    return trainingData.map((m) => m.stages.length).sum;
  }
}

class EloEvaluation {
  final int id;
  final EloSettings settings;
  final double error;

  EloEvaluation(this.id, this.settings, {required this.error});
}

class EloTuner {
  /// A map of training data. Each entry represents a set of data on
  /// which to evaluate settings.
  Map<String, EloEvaluationData> trainingData;

  EloTuner(List<EloEvaluationData> data, {int gridSize = 18, required this.callback}) :
        trainingData = {}..addEntries(data.map((d) => MapEntry(d.name, d))),
        maxEvaluations = {}..addEntries(EloEvaluator.evaluationFunctions.values.map((f) => MapEntry(f, 0.0))),
        grid = PredatorPreyGrid<EloEvaluator>(gridSize: gridSize, evaluations: EloEvaluator.evaluationFunctions.values.toList());

  /// Chance for random mutations in genomes. Applied per variable.
  static const mutationChance = 0.10;
  /// The number of crossovers in k-point crossover.
  static const crossoverPoints = 2;
  /// Retain this proportion of the best population from
  /// each generation. (The rest will be offspring.)
  static const populationRetentionRatio = 0.1;

  static const movementRatio = 0.5;

  List<EloEvaluator> currentPopulation = [];
  Set<EloEvaluator> nonDominated = {};

  List<EloEvaluator> get evaluatedPopulation => currentPopulation.where((e) => e.evaluated).toList();

  PredatorPreyGrid<EloEvaluator> grid;

  int currentGeneration = 0;
  int totalEvaluations = 0;
  bool paused = false;
  Map<EloEvalFunction, double> maxEvaluations = {};

  Future<void> Function(EvaluationProgressUpdate) callback;

  Future<void> tune() async {

    await callback(EvaluationProgressUpdate(
      currentGeneration: 0,
      currentOperation: "Data Setup",
    ));

    List<Genome> genomes = [];
    genomes.addAll(Iterable.generate(10, (i) => EloSettings().toGenome()));
    genomes.addAll(Iterable.generate((grid.preferredPopulationSize * 1.25).round() - 10, (i) => EloGenome.randomGenome()).toList());

    List<EloEvaluator> initialPopulation = genomes.map((g) => EloGenome.toSettings(g)).map((s) => EloEvaluator(settings: s)).toList();
    initialPopulation.shuffle(_r);

    currentPopulation = [];
    currentPopulation.addAll(initialPopulation);

    print("Tuning with ${initialPopulation.length} genomes and ${trainingData.length} test sets");
    
    for(var p in currentPopulation) {
      Location? placed;
      while(placed == null) {
        placed = grid.placeEntity(p);
      }
    }
    for(var f in EloEvaluator.evaluationFunctions.values.toList()) {
      var predators = List.generate(grid.predatorsPerEvaluation, (index) => Predator<EloEvaluator>(weights: {f: 1}));
      for(var p in predators) {
        Location? placed;
        while(placed == null) {
          placed = grid.placeEntity(p);
        }
      }
    }

    await callback(EvaluationProgressUpdate(
      currentGeneration: 0,
      currentOperation: "Startup",
    ));

    runUntilPaused();
  }

  void _updateNonDominated() {
    nonDominated.clear();

    // Solution A dominates solution B if A is better in all error measures than B.
    // Non-dominated solutions are those for which no solutions are better in all error measures.

    // Check to see if B dominates A, for all B in population. If no B dominates A,
    // A is non-dominated.
    for(var a in currentPopulation) {
      if(!a.evaluated) continue;

      var dominated = false;
      for(var b in currentPopulation) {
        if(a == b) continue;
        if(!b.evaluated) continue;

        if(_dominates(b, a)) {
          dominated = true;
          // print("${b.hashCode} dominates ${a.hashCode}");
          break;
        }
      }
      if(!dominated) {
        nonDominated.add(a);
      }
    }
  }

  bool _dominates(EloEvaluator top, EloEvaluator bottom) {
    for(var f in EloEvaluator.evaluationFunctions.values.toList()) {
      /// We're minimizing, so a dominant solution has errors all lower
      /// than its... dominee?
      if(bottom.evaluations[f]! < top.evaluations[f]!) {
        return false;
      }
    }
    return true;
  }

  Future<void> runUntilPaused() async {
    while(!paused) {
      await runGeneration(callback);
      currentGeneration += 1;
      await callback(EvaluationProgressUpdate(
        currentGeneration: currentGeneration,
        currentOperation: "Updating nondominated solutions",
      ));
      _updateNonDominated();
    }

    print("After $currentGeneration generations, ${nonDominated.length} non-dominated solutions exist.");
  }

  Future<void> runGeneration(Future<void> Function(EvaluationProgressUpdate) callback) async {
    print("Starting generation $currentGeneration with ${currentPopulation.length} members");
    
    int genomeIndex = 0;
    var totalDuration = 0;
    var sw = Stopwatch();

    await callback(EvaluationProgressUpdate(
      currentGeneration: currentGeneration,
      currentOperation: "Moving prey",
    ));

    // move prey
    Set<EloEvaluator> moved = {};
    for(int i = 0; i < 10; i++) {
      if(moved.length == currentPopulation.length) {
        break;
      }

      for (var p in currentPopulation) {
        if(moved.contains(p)) continue;

        if(!p.evaluated) {
          int totalProgress = 0;
          int totalSteps = trainingData.values.map((d) => d.trainingData.length).sum;
          for(var data in trainingData.values) {
            await p.evaluate(data, (progress, total) async {
              totalProgress += progress;
              await callback(EvaluationProgressUpdate(
                currentGeneration: currentGeneration,
                currentOperation: "Evaluating genome ${p.hashCode}",
                evaluationTarget: p.settings.toGenome(),
                evaluationProgress: totalProgress,
                evaluationTotal: totalSteps,
              ));
            });
          }
          for(var f in EloEvaluator.evaluationFunctions.values.toList()) {
            var e = f(p);
            p.evaluations[f] = e;
            if(e > maxEvaluations[f]!) {
              maxEvaluations[f] = e;
            }
          }
          _updateNonDominated();
          totalEvaluations += 1;
          await callback(EvaluationProgressUpdate(
            currentGeneration: currentGeneration,
            currentOperation: "Moving prey",
          ));
        }

        if(_r.nextDouble() < 0.5) {
          moved.add(p);
          continue;
        }

        grid.move(p);
        moved.add(p);
      }
    }

    await callback(EvaluationProgressUpdate(
      currentGeneration: currentGeneration,
      currentOperation: "Moving predators",
    ));
    // do predator steps
    int predatorSteps = grid.predatorSteps;
    print("$predatorSteps predator actions");

    int preyEaten = 0;
    // get predators once, rather than at every loop iteration
    // (oops)
    var predators = grid.predators;
    for(var pred in predators) {
      for (int i = 0; i < predatorSteps; i++) {
        var adjacentPrey = grid.preyNeighbors(pred.location!);
        var target = pred.worstPrey(adjacentPrey);
        print("Predator ${pred.hashCode} at ${pred.location} has ${adjacentPrey.length} neighboring prey");

        if (target == null) {
          grid.move(pred);
        }
        else {
          print("Predator eats ${target.hashCode} at ${target.location}!");
          grid.replaceEntity(target.location!, pred);
          currentPopulation.remove(target);
          preyEaten += 1;
        }
        await callback(EvaluationProgressUpdate(
          currentGeneration: currentGeneration,
          currentOperation: "Moving predators",
        ));
      }
    }

    print("${predators.length} predators ate $preyEaten prey, for a current population of ${currentPopulation.length}");

    await callback(EvaluationProgressUpdate(
      currentGeneration: currentGeneration,
      currentOperation: "Breeding prey",
    ));
    // breed prey
    List<EloEvaluator> toPlace = [];
    for(var p1 in grid.prey) {
      var neighbors = grid.preyNeighbors(p1.location!);
      if(neighbors.isNotEmpty) {
        var p2 = neighbors[_r.nextInt(neighbors.length)];

        var p1Settings = p1.settings;
        var p2Settings = p2.settings;

        var childSettings = EloGenome.toSettings(Genome.breed(p1Settings.toGenome(), p2Settings.toGenome(), crossoverPoints: crossoverPoints, mutationChance: mutationChance));
        var child = EloEvaluator(settings: childSettings);

        toPlace.add(child);
      }
      else {
        print("${p1.hashCode} has ${neighbors.length} neighboring prey");
      }
    }

    print("${toPlace.length} new children");

    for(var child in toPlace) {
      var location = grid.placeEntity(child);
      if(location != Location(-1, -1)) {
        currentPopulation.add(child);
      }
    }

    print("After breeding, ${currentPopulation.length} prey");
  }

  EloSettings _pickFrom(List<EloEvaluator> evaluators, weightThresholds, [EloSettings? exclude]) {
    double roll = _r.nextDouble();
    for(int i = 0; i < evaluators.length; i++) {
      // The first time the roll is below the weight threshold, that's the one we want
      if(roll < weightThresholds[i] && evaluators[i].settings != exclude) {
        print("Chose the ${i}th best for breeding");
        return evaluators[i].settings;
      }
    }

    // If we pick the last one twice, pick the second-to-last one instead.
    return evaluators[evaluators.length - 2].settings;
  }

  List<double> _calculateWeights(int count) {
    List<double> nonNormalized = [];
    for(int i = 0; i < count; i++) {
      nonNormalized.add(math.exp(-0.1 * i));
    }
    var sum = nonNormalized.sum;
    var normalized = nonNormalized.map((v) => v / sum).toList();

    List<double> thresholds = [];
    double accumulator = 0;
    for(var w in normalized) {
      accumulator += w;
      thresholds.add(accumulator);
    }

    return thresholds;
  }

  static EloSettings breed(EloSettings a, EloSettings b) {
    var gA = a.toGenome();
    var gB = b.toGenome();

    var child = Genome.breed(gA, gB, crossoverPoints: crossoverPoints, mutationChance: mutationChance);

    return EloGenome.toSettings(child);
  }
}

enum EvolutionAction {
  /// child gets b's genetic data, or 75% B
  /// for continuous parameters
  change,
  /// child gets a mix of a and b genetic data
  blend,
  /// child gets a's genetic data, or 75% A
  /// for continuous parameters
  keep;
}

extension EvolutionActionChoice on List<EvolutionAction> {
  EvolutionAction choose() {
    return this[_r.nextInt(this.length)];
  }
}

extension EloGenome on EloSettings {
  static final kTrait = ContinuousTrait("K", 10, 120);
  static final baseTrait = ContinuousTrait("Probability base", 2, 20);
  static final pctWeightTrait = PercentTrait("Percent weight");
  static final scaleTrait = IntegerTrait("Scale", 200, 1500);
  static final matchBlendTrait = PercentTrait("Match blend");
  static final errorAwareTrait = BoolTrait("Error aware");

  static final errorAwareMaxAsPercentScaleTrait = ContinuousTrait("Error aware max", 0.05, 0.75);
  static final errorAwareMinAsPercentMaxTrait = PercentTrait("Error aware min");
  static final errorAwareZeroAsPercentMinTrait = PercentTrait("Error aware zero");

  /// In UI terms, 1.5 to 5.0
  static final errorAwareUpperMultiplierTrait = ContinuousTrait("Error aware upper mult.", 0.5, 4.0);
  /// In UI terms, 1 to 0.25
  static final errorAwareLowerMultiplierTrait = ContinuousTrait("Error aware lower mult.", 0.0, 0.75);

  static final List<NumTrait> traits = [
    kTrait,
    baseTrait,
    pctWeightTrait,
    scaleTrait,
    matchBlendTrait,
    errorAwareTrait,
    errorAwareMaxAsPercentScaleTrait,
    errorAwareMinAsPercentMaxTrait,
    errorAwareZeroAsPercentMinTrait,
    errorAwareUpperMultiplierTrait,
    errorAwareLowerMultiplierTrait,
  ];

  Genome toGenome() {
    return Genome(
      continuousTraits: {
        kTrait: this.K,
        baseTrait: this.probabilityBase,
        pctWeightTrait: this.percentWeight,
        matchBlendTrait: this.matchBlend,
        errorAwareZeroAsPercentMinTrait: this.errorAwareZeroValue / this.errorAwareMinThreshold,
        errorAwareMinAsPercentMaxTrait: this.errorAwareMinThreshold / this.errorAwareMaxThreshold,
        errorAwareMaxAsPercentScaleTrait: this.errorAwareMaxThreshold / this.scale,
        errorAwareUpperMultiplierTrait: this.errorAwareUpperMultiplier,
        errorAwareLowerMultiplierTrait: this.errorAwareLowerMultiplier,
      },
      intTraits: {
        scaleTrait: this.scale.round(),
        errorAwareTrait: BoolTrait.encode(this.errorAwareK),
      }
    );
  }

  static Genome randomGenome() {
    return Genome(
      continuousTraits: {
        kTrait: kTrait.random,
        baseTrait: baseTrait.random,
        pctWeightTrait: pctWeightTrait.random,
        matchBlendTrait: matchBlendTrait.random,
        errorAwareZeroAsPercentMinTrait: errorAwareZeroAsPercentMinTrait.random,
        errorAwareMinAsPercentMaxTrait: errorAwareMinAsPercentMaxTrait.random,
        errorAwareMaxAsPercentScaleTrait: errorAwareMaxAsPercentScaleTrait.random,
        errorAwareUpperMultiplierTrait: errorAwareUpperMultiplierTrait.random,
        errorAwareLowerMultiplierTrait: errorAwareLowerMultiplierTrait.random,
      },
      intTraits: {
        scaleTrait: scaleTrait.random,
        errorAwareTrait: errorAwareTrait.random,
      }
    );
  }

  static EloSettings toSettings(Genome g) {
    var traits = g.traits;

    var scale = traits[scaleTrait]!.toDouble();
    var errorMaxThreshold = traits[errorAwareMaxAsPercentScaleTrait]!.toDouble() * scale;
    var errorMinThreshold = traits[errorAwareMinAsPercentMaxTrait]!.toDouble() * errorMaxThreshold;
    var errorZero = traits[errorAwareZeroAsPercentMinTrait]!.toDouble() * errorMinThreshold;

    return EloSettings(
      byStage: true,
      K: traits[kTrait]!.toDouble(),
      probabilityBase: traits[baseTrait]!.toDouble(),
      percentWeight: traits[pctWeightTrait]!.toDouble(),
      scale: traits[scaleTrait]!.toDouble(),
      matchBlend: traits[matchBlendTrait]!.toDouble(),
      errorAwareK: BoolTrait.decode(traits[errorAwareTrait]!.toInt()),
      errorAwareMaxThreshold: errorMaxThreshold,
      errorAwareMinThreshold: errorMinThreshold,
      errorAwareZeroValue: errorZero,
      errorAwareLowerMultiplier: traits[errorAwareLowerMultiplierTrait]!.toDouble(),
      errorAwareUpperMultiplier: traits[errorAwareUpperMultiplierTrait]!.toDouble(),
    );
  }
}

class EvaluationProgressUpdate {
  int currentGeneration;
  Genome? evaluationTarget;
  int? evaluationProgress;
  int? evaluationTotal;
  String currentOperation;

  EvaluationProgressUpdate({
    required this.currentGeneration,
    required this.currentOperation,
    this.evaluationTarget,
    this.evaluationProgress,
    this.evaluationTotal,
  });
}