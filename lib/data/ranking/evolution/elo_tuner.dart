import 'package:collection/collection.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/ranking/evolution/genome.dart';
import 'package:uspsa_result_viewer/data/ranking/evolution/predator_prey.dart';
import 'package:uspsa_result_viewer/data/ranking/model/shooter_rating.dart';
import 'package:uspsa_result_viewer/data/ranking/project_manager.dart';
import 'package:uspsa_result_viewer/data/ranking/rater.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/elo/elo_rater_settings.dart';
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
6? Minimize rating error at the terminal end of calibration.

I may think of others, but this is a pretty good set to start with.

I think, for the collection of
 */

class EloEvaluator extends Prey {
  /// The settings used for this iteration.
  EloSettings settings;

  /// The calculated errors for each set of predictions.
  Map<String, double> errors = {};

  /// The total error across all predictions in the training
  /// set, which is the quantity we want to minimize.
  double get totalError => errors.values.sum;

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
    print("Matches processed");

    var rater = h.raterFor(h.matches.last, data.group);

    print("Predicting matches and validating predictions");
    for(var m in data.evaluationData) {
      Map<Shooter, ShooterRating> registrations = {};
      for(var shooter in m.shooters) {
        var rating = rater.knownShooters[Rater.processMemberNumber(shooter.memberNumber)];
        if(rating != null )registrations[shooter] = rating;
      }

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
          predictions: predictions
      );

      errors[data.name] = evaluations.error;
    }
    print("Validation done");

    return totalError;
  }
}

class EloEvaluationData {
  final String name;
  final List<PracticalMatch> trainingData;
  final List<PracticalMatch> evaluationData;
  final RaterGroup group;

  EloEvaluationData({required this.name, required this.trainingData, required this.evaluationData, required this.group});
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

  EloTuner(List<EloEvaluationData> data) : trainingData = {}..addEntries(data.map((d) => MapEntry(d.name, d)));

  /// Chance for random mutations in genomes. Applied per variable.
  static const mutationChance = 0.05;
  /// The number of crossovers in k-point crossover.
  static const crossoverPoints = 2;
  /// Retain this proportion of the best population from
  /// each generation. (The rest will be offspring.)
  static const populationRetentionRatio = 0.1;

  late List<EloSettings> currentPopulation;

  /// Contains a list of evaluated Elo settings, where the list index is the
  /// generation and the map is from Elo settings to error sums on [trainingData].
  late List<List<EloEvaluation>> evaluations = [];

  Future<void> tune(List<EloSettings> initialPopulation, int generations, Future<void> Function(EvaluationProgressUpdate) callback) async {
    var generation = 0;

    currentPopulation = [];
    currentPopulation.addAll(initialPopulation);

    print("Tuning with ${initialPopulation.length} genomes, $generations generations, and ${trainingData.length} test sets");

    await callback(EvaluationProgressUpdate(
      currentGeneration: 0,
      totalGenerations: generations,
      currentGenome: 0,
      totalGenomes: currentPopulation.length,
      evaluations: evaluations,
      currentTrainingSet: 0,
      totalTrainingSets: trainingData.length,
      currentMatch: 0,
      totalMatches: trainingData[trainingData.keys.first]!.trainingData.length,
    ));

    while(generation < generations) {
      await runGeneration(generation, generations, callback);
      generation += 1;
    }

    var finalEvaluations = evaluations.last;
    var bestSettings = finalEvaluations.sorted((a, b) => a.error.compareTo(b.error));

    print("Tuning complete! Best settings: ${bestSettings.first.settings.toGenome()} with error ${bestSettings.first.error}");
  }

  Future<void> runGeneration(int generation, int totalGenerations, Future<void> Function(EvaluationProgressUpdate) callback) async {
    print("Starting generation $generation with ${currentPopulation.length} members");
    var evaluators = <EloEvaluator>[];

    evaluations.add([]);

    for(var settings in currentPopulation) {
      evaluators.add(EloEvaluator(settings: settings));
    }

    int genomeIndex = 0;
    for(var evaluator in evaluators) {
      int trainingIndex = 0;
      for(var name in trainingData.keys) {
        var data = trainingData[name]!;
        print("Gen $generation: evaluating genome $genomeIndex on $name");
        await evaluator.evaluate(trainingData[name]!, (current, total) async {
          await callback(EvaluationProgressUpdate(
            currentGeneration: generation,
            totalGenerations: totalGenerations,
            currentGenome: genomeIndex,
            totalGenomes: currentPopulation.length,
            evaluations: evaluations,
            currentTrainingSet: trainingIndex,
            totalTrainingSets: trainingData.length,
            currentMatch: current * RatingHistory.progressCallbackInterval,
            totalMatches: data.trainingData.length,
          ));
        });
        trainingIndex += 1;
      }

      evaluations.last.add(EloEvaluation(genomeIndex, evaluator.settings, error: evaluator.totalError));
      evaluations.last.sort((a, b) => a.error.compareTo(b.error));

      await callback(EvaluationProgressUpdate(
        currentGeneration: generation,
        totalGenerations: totalGenerations,
        currentGenome: genomeIndex,
        totalGenomes: currentPopulation.length,
        evaluations: evaluations,
        currentTrainingSet: trainingIndex,
        totalTrainingSets: trainingData.length,
        currentMatch: 0,
        totalMatches: 0,
      ));
      trainingIndex += 1;

      print("Gen $generation: total error for $genomeIndex: ${evaluator.totalError}");

      genomeIndex += 1;
    }

    evaluators.sort((a, b) => a.totalError.compareTo(b.totalError));

    List<EloSettings> newPopulation = [];
    // Keep top N
    int toKeep = (currentPopulation.length * populationRetentionRatio).round();
    for(int i = 0; i < toKeep; i++) newPopulation.add(evaluators[i].settings);

    // Breed the rest, picking from a weighted list

    int remaining = currentPopulation.length - toKeep;
    List<double> weightThresholds = _calculateWeights(currentPopulation.length);
    for(int i = 0; i < remaining; i++) {
      var parentA = _pickFrom(evaluators, weightThresholds);
      var parentB = _pickFrom(evaluators, weightThresholds, parentA);

      var newSettings = EloTuner.breed(parentA, parentB);
      newPopulation.add(newSettings);
    }

    currentPopulation = newPopulation;

    print("Generation $generation complete");
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
  int totalGenerations;
  int currentGenome;
  int totalGenomes;
  int currentTrainingSet;
  int totalTrainingSets;
  int currentMatch;
  int totalMatches;

  List<List<EloEvaluation>> evaluations;

  EvaluationProgressUpdate({
    required this.currentGeneration,
    required this.totalGenerations,
    required this.currentGenome,
    required this.totalGenomes,
    required this.evaluations,
    required this.currentTrainingSet,
    required this.totalTrainingSets,
    required this.currentMatch,
    required this.totalMatches,
  });
}