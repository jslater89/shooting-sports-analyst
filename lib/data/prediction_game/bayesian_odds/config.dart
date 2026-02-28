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
  final double lambda;

  /// Constant for conviction log transform: log(1 + rawConviction * convictionLogK) / log(1 + convictionLogK)
  ///
  /// 5 yields 0.65 for 0.20 raw conviction.
  ///
  /// 0 yields no transform.
  final double convictionLogK;

  /// Minimum floor for conviction, after log transform, in [0-1] space.
  final double convictionFloor;

  /// Default conviction value to use if maxWager is not available.
  final double defaultConviction;

  /// Maximum base logit shift for odds movement, in logit space.
  ///
  /// 1.0 means the odds can roughly double or halve at most
  /// from a single update.
  ///
  /// maxLogitShift is further adjusted by the total weight of evidence
  /// on the shooter.
  final double maxLogitShift;

  /// Clamp factor for evidence-dependent logit shift. If >0, as more
  /// evidence (in the form of bet weights) accumulates on a shooter,
  /// the allowed shift in log space grows. This scales the speed of
  /// the shift.
  final double clampEvidenceK;

  /// Baseline bet weight for evidence-dependent logit shift. The total
  /// weight of evidence on the shooter is divided by this value to
  /// create the parameter to log() for evidence-dependent logit shift.
  final double clampBaselineWeight;

  /// Maximum multiplier for evidence-dependent logit shift. [maxLogitShift]
  /// will be multiplied by no more than this much as a result of accumulated
  /// evidence.
  final double clampMaxMultiplier;


  /// Minimum number of resolved bets for sharpness adjustment to be applied.
  final double minSharpnessBets;

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
    double? lambda,
    double? convictionLogK,
    double? convictionFloor,
    double? defaultConviction,
    double? maxLogitShift,
    double? clampEvidenceK,
    double? clampBaselineWeight,
    double? clampMaxMultiplier,
    double? minSharpnessBets,
    double? sharpnessClampMin,
    double? sharpnessClampMax,
    double? percentageSimilarityMaxDistance,
    double? percentageSimilaritySteepness,
  })  : nEffScale = nEffScale ?? 10,
        nEffMin = nEffMin ?? 20,
        nEffMax = nEffMax ?? 150,
        nEffLogBase = nEffLogBase,
        baseWeight = baseWeight ?? 10,
        lambda = lambda ?? 0.02,
        convictionLogK = convictionLogK ?? 5,
        convictionFloor = convictionFloor ?? 0.05,
        defaultConviction = defaultConviction ?? 0.75,
        maxLogitShift = maxLogitShift ?? 1.0,
        clampEvidenceK = clampEvidenceK ?? 0.2,
        clampBaselineWeight = clampBaselineWeight ?? 1,
        clampMaxMultiplier = clampMaxMultiplier ?? 2,
        minSharpnessBets = minSharpnessBets ?? 5,
        sharpnessClampMin = sharpnessClampMin ?? 0.5,
        sharpnessClampMax = sharpnessClampMax ?? 2.0,
        percentageSimilarityMaxDistance = percentageSimilarityMaxDistance ?? 0.05,
        percentageSimilaritySteepness = percentageSimilaritySteepness ?? 20;
}