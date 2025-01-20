/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */


import 'package:collection/collection.dart';
import 'package:shooting_sports_analyst/data/ranking/evolution/elo_evaluation.dart';
import 'package:shooting_sports_analyst/data/ranking/evolution/genome.dart';
import 'package:shooting_sports_analyst/data/ranking/evolution/predator_prey.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/elo/elo_rater_settings.dart';
import 'package:shooting_sports_analyst/data/ranking/legacy_loader/rating_history.dart';
import 'dart:math' as math;

import 'package:shooting_sports_analyst/logger.dart';

var _log = SSALogger("EloTuner");

var _r = math.Random();

class EloTuner {
  /// A map of training data. Each entry represents a set of data on
  /// which to evaluate settings.
  Map<String, EloEvaluationData> trainingData;

  EloTuner(List<EloEvaluationData> data, {int gridSize = 24, required this.callback}) :
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
  Map<EloEvalFunction, double> firstGenerationMaximums = {};

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

    for(var evalFn in EloEvaluator.evaluationFunctions.values) {
      firstGenerationMaximums[evalFn] = 0;
    }

    List<Genome> genomes = [];
    genomes.addAll(Iterable.generate(10, (i) => EloSettings().toGenome()));
    genomes.addAll(Iterable.generate((grid.preferredPopulationSize * 1.1).round() - 10, (i) => EloGenome.randomGenome()).toList());

    List<EloEvaluator> initialPopulation = genomes.map((g) => EloGenome.toSettings(g)).map((s) => EloEvaluator(generation: 0, settings: s)).toList();
    initialPopulation.shuffle(_r);

    currentPopulation = [];
    currentPopulation.addAll(initialPopulation);

    _log.d("Tuning with ${initialPopulation.length} genomes and ${trainingData.length} test sets");
    
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
          // _log.d("${b.hashCode} dominates ${a.hashCode}");
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

    _log.d("After $currentGeneration generations, ${nonDominated.length} non-dominated solutions exist.");
  }

  Future<void> runGeneration(Future<void> Function(EvaluationProgressUpdate) callback) async {
    _log.d("Starting generation $currentGeneration with ${currentPopulation.length} members");
    
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
          int totalSteps = trainingData.values.map((d) => (d.trainingData.length / OldRatingHistory.progressCallbackInterval).round() + d.evaluationData.length).sum;
          sw.reset();
          sw.start();
          for(var data in trainingData.values) {
            int lastProgress = 0;
            await p.evaluate(data, (progress, total) async {
              totalProgress += (progress - lastProgress);
              lastProgress = progress;
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
          sw.stop();
          _log.d("Evaluation took ${sw.elapsedMilliseconds / 1000}s");
        }

        if(currentGeneration == 0) {
          for(var evalName in EloEvaluator.evaluationFunctions.keys) {
            var evalFn = EloEvaluator.evaluationFunctions[evalName]!;

            var eval = p.evaluations[evalFn]!;
            if(eval > firstGenerationMaximums[evalFn]!) {
              firstGenerationMaximums[evalFn] = eval;
            }
          }
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
    _log.d("$predatorSteps predator actions");

    int preyEaten = 0;
    // get predators once, rather than at every loop iteration
    // (oops)
    var predators = grid.predators;
    for(var pred in predators) {
      for (int i = 0; i < predatorSteps; i++) {
        var adjacentPrey = grid.preyNeighbors(pred.location!);
        var target = pred.worstPrey(adjacentPrey);
        _log.d("Predator ${pred.hashCode} at ${pred.location} has ${adjacentPrey.length} neighboring prey");

        if (target == null) {
          grid.move(pred);
        }
        else {
          _log.d("Predator eats ${target.hashCode} at ${target.location}!");
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

    _log.d("${predators.length} predators ate $preyEaten prey, for a current population of ${currentPopulation.length}");

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
        var child = EloEvaluator(generation: currentGeneration + 1, settings: childSettings);

        toPlace.add(child);
      }
      else {
        _log.d("${p1.hashCode} has ${neighbors.length} neighboring prey");
      }
    }

    _log.d("${toPlace.length} new children");

    for(var child in toPlace) {
      var location = grid.placeEntity(child);
      if(location != null) {
        currentPopulation.add(child);
      }
    }

    _log.d("After breeding, ${currentPopulation.length} prey");
  }

  EloSettings _pickFrom(List<EloEvaluator> evaluators, weightThresholds, [EloSettings? exclude]) {
    double roll = _r.nextDouble();
    for(int i = 0; i < evaluators.length; i++) {
      // The first time the roll is below the weight threshold, that's the one we want
      if(roll < weightThresholds[i] && evaluators[i].settings != exclude) {
        _log.d("Chose the ${i}th best for breeding");
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