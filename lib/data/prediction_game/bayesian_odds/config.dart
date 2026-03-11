import 'package:shooting_sports_analyst/util.dart';

class BayesianOddsConfig {
  // Parameters for nEff, the effective sample size.
  // nEff is calculated from shooter rating history length
  // in stages: clamp(nEffMin, nEffScale * log(1 + historyCount), nEffMax)

  /// nEff scale
  final double nEffScale;

  /// Minimum nEff.
  final double nEffMin;

  /// Maximum nEff.
  final double nEffMax;

  /// nEff log base. If not present,
  /// default to e.
  final double? nEffLogBase;

  /// Base weight for bayesian updates.
  final double baseWeight;

  /// Lambda for exponential time decay, 1 - exp(-lambda * daysUntilMatch)
  ///
  /// 0.02 gives ~half weight at 30 days out.
  final double timeDecayLambda;

  /// Constant for conviction log transform: log(1 + rawConviction * convictionLogK) / log(1 + convictionLogK)
  ///
  /// 5 yields 0.65 for 0.20 raw conviction.
  ///
  /// 0 yields no transform.
  final double convictionLogK;

  /// Output floor for conviction: transform maps to [convictionFloor, 1].
  /// After the log transform (which yields [0, 1]), conviction is rescaled to
  /// convictionFloor + (1 - convictionFloor) * logTransform(raw), so the output
  /// is in [convictionFloor, 1]. Use 0 for no floor (output [0, 1]).
  final double convictionFloor;

  /// Default conviction value to use if maxWager is not available.
  ///
  /// This value is in raw conviction space, and will be log-mapped/scaled according
  /// to convictionLogK and convictionFloor.
  final double defaultConviction;


  /// Maximum base logit shift for odds movement, in logit space.
  ///
  /// 1.0 means the odds can roughly double or halve at most
  /// from a single update.
  ///
  /// maxLogitShift is further adjusted by the total weight of evidence
  /// on the shooter.
  final double maxLogitShift;

  /// Characteristic weight for evidence-dependent logit shift. This is the
  /// total bet weight at which the clamp multiplier reaches ~63% of the way
  /// from 1.0 to [clampMaxMultiplier]. Set to 0 or negative to disable
  /// evidence-dependent scaling (fixed clamp at [maxLogitShift]).
  ///
  /// Formula: multiplier = 1 + (clampMaxMultiplier - 1) * (1 - exp(-totalWeight / clampEvidenceTau))
  final double clampEvidenceTau;

  /// Maximum multiplier for evidence-dependent logit shift. [maxLogitShift]
  /// will be multiplied by no more than this much as a result of accumulated
  /// evidence.
  final double clampMaxMultiplier;

  /// Minimum number of resolved bets for sharpness adjustment to be applied.
  final int minSharpnessBets;

  /// Minimum multiplier permitted for sharpness.
  final double sharpnessClampMin;

  /// Maximum multiplier permitted for sharpness.
  final double sharpnessClampMax;

  /// Maximum distance between two percentage predictions for similarity to be considered.
  final double percentageSimilarityMaxDistance;

  /// Steepness of the sigmoid curve for percentage similarity.
  final double percentageSimilaritySteepness;

  BayesianOddsConfig({
    double? nEffScale,
    double? nEffMin,
    double? nEffMax,
    double? nEffLogBase,
    double? baseWeight,
    double? timeDecayLambda,
    double? convictionLogK,
    double? convictionFloor,
    double? defaultConviction,
    double? maxLogitShift,
    double? clampEvidenceTau,
    double? clampMaxMultiplier,
    int? minSharpnessBets,
    double? sharpnessClampMin,
    double? sharpnessClampMax,
    double? percentageSimilarityMaxDistance,
    double? percentageSimilaritySteepness,
  })  : nEffScale = nEffScale ?? 10,
        nEffMin = nEffMin ?? 20,
        nEffMax = nEffMax ?? 150,
        nEffLogBase = nEffLogBase,
        baseWeight = baseWeight ?? 20,
        timeDecayLambda = timeDecayLambda ?? 0.02,
        convictionLogK = convictionLogK ?? 5,
        convictionFloor = convictionFloor ?? 0.25,
        defaultConviction = defaultConviction ?? 0.33,
        maxLogitShift = maxLogitShift ?? 1.0,
        clampEvidenceTau = clampEvidenceTau ?? 50.0,
        clampMaxMultiplier = clampMaxMultiplier ?? 2,
        minSharpnessBets = minSharpnessBets ?? 5,
        sharpnessClampMin = sharpnessClampMin ?? 0.5,
        sharpnessClampMax = sharpnessClampMax ?? 2.0,
        percentageSimilarityMaxDistance = percentageSimilarityMaxDistance ?? 0.05,
        percentageSimilaritySteepness = percentageSimilaritySteepness ?? 20;

  int get configHash => combineHashList64([
    nEffScale.stableHash64,
    nEffMin.stableHash64,
    nEffMax.stableHash64,
    nEffLogBase?.stableHash64 ?? 0,
    baseWeight.stableHash64,
    timeDecayLambda.stableHash64,
    convictionLogK.stableHash64,
    convictionFloor.stableHash64,
    defaultConviction.stableHash64,
    maxLogitShift.stableHash64,
    clampEvidenceTau.stableHash64,
    clampMaxMultiplier.stableHash64,
    minSharpnessBets.stableHash64,
    sharpnessClampMin.stableHash64,
    sharpnessClampMax.stableHash64,
    percentageSimilarityMaxDistance.stableHash64,
    percentageSimilaritySteepness.stableHash64,
  ]);
}