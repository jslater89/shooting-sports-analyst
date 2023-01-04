import 'dart:math';

import 'package:collection/collection.dart';
import 'package:uspsa_result_viewer/data/match/practical_match.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/elo/elo_rater_settings.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/elo/multiplayer_percent_elo_rater.dart';
import 'package:uspsa_result_viewer/data/ranking/rating_history.dart';
import 'dart:math' as math;


var _r = Random();

class EloEvaluator {
  /// The settings used for this iteration.
  EloSettings settings;

  /// The calculated errors for each set of predictions.
  Map<RatingHistory, double> errors = {};

  /// The total error across all predictions in the training
  /// set, which is the quantity we want to minimize.
  double get totalError => errors.values.sum;

  EloEvaluator({
    required this.settings,
  });

  Future<double> evaluate(List<PracticalMatch> matches, List<PracticalMatch> tests, RaterGroup group) async {
    var h = RatingHistory(matches: matches, settings: RatingHistorySettings(
      algorithm: MultiplayerPercentEloRater(settings: settings),
      groups: [group],
    ));

    await h.processInitialMatches();

    var rater = h.raterFor(h.matches.last, group);

    double errorSum = 0;

    for(var m in tests) {
      // TODO: registrations
      var predictions = rater.ratingSystem.predict([]);

      var evaluations = rater.ratingSystem.validate(
          shooters: [],
          scores: scores,
          matchScores: matchScores,
          predictions: predictions
      );

      errors[h] = evaluations.error;
    }

    return totalError;
  }
}

class EloTuner {
  /// A map of training data. Each entry represents a set of data on
  /// which to evaluate settings.
  ///
  /// The settings
  Map<List<PracticalMatch>, List<PracticalMatch>> trainingData;

  EloTuner({required this.trainingData});

  /// Chance for random mutations in genomes. Applied per variable.
  static const mutationChance = 0.01;
  /// Mutations will change variables by no more than this much of their
  /// total range.
  static const mutationVolatility = 1.0;
  /// Mutations can go this far above min or below max.
  static const mutationRangeExtension = 0.25;
  /// The number of crossovers in k-point crossover.
  static const crossoverPoints = 2;
  /// Retain this proportion of the best population from
  /// each generation. (The rest will be offspring.)
  static const populationRetentionRatio = 0.1;

  late List<EloSettings> currentPopulation;

  Future<void> tune(List<EloSettings> initialPopulation, int generations) async {
    var generation = 0;

    currentPopulation = [];
    currentPopulation.addAll(initialPopulation);

    while(generation < generations) {
      runGeneration();
    }

  }

  Future<void> runGeneration() async {
    var evaluators = <EloEvaluator>[];
    for(var settings in currentPopulation) {
      // make, predict, evaluate
    }

    evaluators.sort((a, b) => a.totalError.compareTo(b.totalError));
  }

  static EloSettings breed(EloSettings a, EloSettings b) {
    var gA = a.toGenome();
    var gB = b.toGenome();
    var child = Genome();

    // k-point crossover

    List<int> crossoverIndices = List.generate(EloGenome.traits.length, (i) => i)..shuffle()..sublist(0, crossoverPoints)..sort();
    EvolutionAction action = EvolutionAction.values.choose();

    for(int i = 0; i < EloGenome.traits.length; i++) {
      // Pick a new action when we hit a crossover index
      if(crossoverIndices.isNotEmpty && i == crossoverIndices[0]) {
        crossoverIndices.removeAt(0);
        action = EvolutionAction.values.choose();
      }

      var trait = EloGenome.traits[i];
      var tA = gA.traits[trait]!;
      var tB = gB.traits[trait]!;
      switch(action) {
        case EvolutionAction.change:
          var value = trait.breed(tA, tB, -0.25);
          child.setTrait(trait, value);
          break;
        case EvolutionAction.blend:
          var value = trait.breed(tA, tB);
          child.setTrait(trait, value);
          break;
        case EvolutionAction.keep:
          var value = trait.breed(tA, tB, 0.25);
          child.setTrait(trait, value);
          break;
      }
    }

    // mutation
    for(var trait in EloGenome.traits) {
      if(_r.nextDouble() < mutationChance) {
        // That's not a pretty line.
        child.setTrait(trait, trait.mutate(child.traits[trait]!));
      }
    }

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

class Genome {
  Map<ContinuousTrait, double> continuousTraits;
  Map<IntegerTrait, int> intTraits;

  Genome({
    this.continuousTraits = const {},
    this.intTraits = const {},
  });

  int get length => continuousTraits.length + intTraits.length;
  Map<NumTrait, num> get traits => Map.fromEntries([...continuousTraits.entries, ...intTraits.entries]);

  void setTrait(NumTrait trait, num value) {
    if(trait is ContinuousTrait) {
      continuousTraits[trait] = value as double;
    }
    else if(trait is IntegerTrait) {
      intTraits[trait] = value as int;
    }
  }
}

extension EloGenome on EloSettings {
  static final kTrait = ContinuousTrait(10, 100);
  static final baseTrait = ContinuousTrait(2, 20);
  static final pctWeightTrait = PercentTrait();
  static final scaleTrait = IntegerTrait(200, 1000);
  static final matchBlendTrait = PercentTrait();
  static final errorAwareTrait = BoolTrait();

  static final errorAwareMaxAsPercentScaleTrait = ContinuousTrait(0.1, 1.5);
  static final errorAwareMinAsPercentMaxTrait = PercentTrait();
  static final errorAwareZeroAsPercentMinTrait = PercentTrait();

  /// In UI terms, 1.5 to 5.0
  static final errorAwareUpperMultiplierTrait = ContinuousTrait(0.5, 4.0);
  /// In UI terms, 1 to 0.25
  static final errorAwareLowerMultiplierTrait = ContinuousTrait(0.0, 0.75);

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
        errorAwareMinAsPercentMaxTrait: this.errorAwareMinThreshold / this.scale,
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

abstract class NumTrait {
  num get min;
  num get max;

  num get range;
  num get random;

  num get softMax => max + max * EloTuner.mutationRangeExtension;
  num get softMin => min - min * EloTuner.mutationRangeExtension;

  num clamp(num n, num min, num max) {
    return n.clamp(min, max);
  }

  // blend two values from this trait
  num breed(covariant num a, covariant num b, [double aWeight = 0.0]);

  // mutate this trait
  num mutate(covariant num a);
}

class ContinuousTrait extends NumTrait {
  final double min;
  final double max;

  ContinuousTrait(this.min, this.max);

  double get range => max - min;
  double get random => _r.nextDouble() * range + min;

  double breed(double a, double b, [double aWeight = 0.0]) {
    var proportion = _r.nextDouble();

    // If aWeight is 0.25, we want [0.0..0.75], so proportion is tilted toward A.
    //
    // If aWeight is -0.25, we want [0.25..1], so proportion is tilted toward B.
    proportion = proportion * (1 - aWeight.abs());
    if(aWeight < 0) proportion += aWeight.abs();

    return clamp(a * proportion + b * (1 - proportion), softMin, softMax).toDouble();
  }

  double mutate(double a) {
    var mutationMagnitude = _r.nextDouble() * range * EloTuner.mutationVolatility;
    var mutation = mutationMagnitude * (_r.nextBool() ? 1 : -1);

    return a + mutation;
  }
}

class PercentTrait extends ContinuousTrait {
  PercentTrait() : super(0, 1);

  @override
  num clamp(num n, num min, num max) {
    return n.clamp(min, max);
  }

  @override
  double get range => 1;
}

class IntegerTrait extends NumTrait {
  final int min;
  final int max;

  IntegerTrait(this.min, this.max);

  int get range => max - min;
  int get random => _r.nextInt(range + 1) + min;

  int mutate(int a) {
    var mutationAmount = (range * EloTuner.mutationVolatility).round();
    var mutation = mutationAmount * (_r.nextBool() ? 1 : -1);

    return a + mutation;
  }

  int breed(int a, int b, [double aWeight = 0.0]) {
    var proportion = _r.nextDouble();

    // If aWeight is 0.25, we want [0.0..0.75], so proportion is tilted toward A.
    //
    // If aWeight is -0.25, we want [0.25..1], so proportion is tilted toward B.
    proportion = proportion * (1 - aWeight.abs());
    if(aWeight < 0) proportion += aWeight.abs();

    return clamp(a * proportion + b * (1 - proportion), softMin, softMax).round();
  }
}

class BoolTrait extends IntegerTrait {
  BoolTrait() : super(0, 1);

  static bool decode(int v) {
    return v != 0;
  }

  static int encode(bool v) {
    return v ? 1 : 0;
  }

  int mutate(int a) {
    return _r.nextInt(2);
  }

  int breed(int a, int b, [double aWeight = 0.0]) {
    if(aWeight > 0) return a;
    else if(aWeight < 0) return b;
    else return _r.nextInt(2);
  }
}