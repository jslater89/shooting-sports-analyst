import 'package:collection/collection.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/ranking/evolution/genome.dart';
import 'package:uspsa_result_viewer/data/ranking/model/shooter_rating.dart';
import 'package:uspsa_result_viewer/data/ranking/project_manager.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/elo/elo_rater_settings.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/elo/multiplayer_percent_elo_rater.dart';
import 'package:uspsa_result_viewer/data/ranking/rating_history.dart';
import 'dart:math' as math;

var _r = math.Random();

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
    var h = RatingHistory(
      matches: matches,
      project: RatingProject(
        name: "Evolutionary test",
        matchUrls: matches.map((e) => e.practiscoreId).toList(),
        settings: RatingHistorySettings(
          algorithm: MultiplayerPercentEloRater(settings: settings),
          groups: [group],
        )
      )
    );

    await h.processInitialMatches();

    var rater = h.raterFor(h.matches.last, group);

    double errorSum = 0;

    for(var m in tests) {
      Map<Shooter, ShooterRating> registrations = {};

      // TODO: registrations
      var predictions = rater.ratingSystem.predict([]);

      // TODO: only for the shooters we predicted?
      var scoreOutput = m.getScores();

      // TODO: use registration map
      var scores = <ShooterRating, RelativeScore>{};

      var evaluations = rater.ratingSystem.validate(
          shooters: [],
          scores: scores,
          matchScores: scores,
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
  /// The key is a list of matches to be used to generate ratings. The
  /// value is a list of matches to evaluate on.
  Map<List<PracticalMatch>, List<PracticalMatch>> trainingData;

  EloTuner({required this.trainingData});

  /// Chance for random mutations in genomes. Applied per variable.
  static const mutationChance = 0.05;
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
  static final kTrait = ContinuousTrait("K", 10, 100);
  static final baseTrait = ContinuousTrait("Probability base", 2, 20);
  static final pctWeightTrait = PercentTrait("Percent weight");
  static final scaleTrait = IntegerTrait("Scale", 200, 1000);
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