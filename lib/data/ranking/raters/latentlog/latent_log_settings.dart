import 'package:shooting_sports_analyst/data/ranking/model/rating_settings.dart';

class LatentLogSettings extends RaterSettings {
  static const defaultScaleOffset = 1000.0;
  static const defaultScaleFactor = 2250.0;
  static const defaultSportVolatility = 0.0024;
  static const defaultSkillDriftRate = 0.000129;
  static const defaultStartingVariance = 0.0216;
  static const defaultVolatilityAdaptationRate = 0.10;
  static const defaultSurpriseAdaptationRate = 0.07;
  static const defaultPairwiseBlendWeight = 0.10;

  static const _byStageKey = "latentLogByStage";
  static const _scaleOffsetKey = "latentLogScaleOffset";
  static const _scaleFactorKey = "latentLogScaleFactor";
  static const _sportVolatilityKey = "latentLogSportVolatility";
  static const _skillDriftRateKey = "latentLogSkillDriftRate";
  static const _startingVarianceKey = "latentLogStartingVariance";
  static const _volatilityAdaptationRateKey = "latentLogVolatilityAdaptationRate";
  static const _surpriseAdaptationRateKey = "latentLogSurpriseAdaptationRate";
  static const _pairwiseBlendWeightKey = "latentLogPairwiseBlendWeight";

  /// Whether to calculate ratings by stage (true) or by match (false).
  bool byStage;

  /// The scale offset for latent log ratio display units.
  double scaleOffset;

  /// The scale factor for latent log ratio display units.
  double scaleFactor;

  // Tuning parameters below are all given in variance units, but are
  // easier to reason about in standard deviation terms. The derivations
  // below start with finish percentages (as we do in many parts of this system)
  // and convert to variance units.

  /// The sport volatility in variance units, i.e. σ_sport^2 from the paper.
  ///
  /// Interpretation: the mostly-irreducible variance of the sport, i.e.
  /// how much of a swing in performance is expected from one match to the next
  /// for a consistent competitor. How much ln(finish) wiggles around true skill.
  ///
  /// Tuning: e.g. ±5% finish expected (1SD)
  /// -> 1.05 (edge of 1SD)
  /// -> ln(1.05) = 0.049 (log std. dev)
  /// -> 0.049^2 = 0.0024 (variance = sigma^2)
  double sportVolatility = defaultSportVolatility;

  /// The skill drift rate in variance units per rating period, i.e. σ_drift^2 from the paper.
  ///
  /// Interpretation: the amount by which competitor variance increases over one
  /// rating period. How much wider 1SD gets over time. Rating periods are 1 week.
  ///
  /// Tuning: e.g. σ_drift should grow by ±5% over one year (52 rating periods)
  /// -> delta-v per year = ln(1.10)^2 - ln(1.05)^2.
  ///      justification: 5% initial 1SD, 10% 1SD at the end of the year. change
  ///      in variance is the difference between initial_sigma^2 and final_sigma^2.
  /// -> 0.0091 - 0.0024 = 0.0067 (variance)
  /// -> 0.0067 / 52 = 0.000129 (variance per rating period)
  double skillDriftRate = defaultSkillDriftRate;

  /// The variance term for new ratings, and the upper clamp for competitor variance
  /// after skill drift.
  ///
  /// Tuning: 3-4x sport volatility in log space/SD terms, not in variance units.
  ///
  /// sqrt(V_initial) = k * σ_sport
  /// -> V_initial = k^2 * σ_sport^2
  /// -> V_initial = 3^2 * 0.0024 = 0.0216
  /// -> V_initial = 4^2 * 0.0024 = 0.0384
  double startingVariance = defaultStartingVariance;

  // Adaptation rates for the Kalman filter's variance update.

  /// The volatility adaptation rate, i.e. β from the paper.
  ///
  /// Interpretation: controls how fast per-competitor behavioral volatility
  /// (σ_i^2) tracks recent squared innovations. After each update,
  /// σ_i^2 <- (1 - β) * σ_i^2 + β * e_i^2, where e_i = P_i - R_i (same units
  /// as the log rating). High β: σ_i^2 reacts quickly to one wild match;
  /// low β: smooth estimate of "how noisy is this shooter" over many events.
  ///
  /// Tuning: dimensionless in (0, 1). Typical band ~0.05--0.20.
  /// -> 0.05: very stable σ_i^2, slow to reflect a real change in consistency.
  /// -> 0.10: default; moderate memory (~order of 10 events, very loosely).
  /// -> 0.15--0.20: responsive; use if σ_i^2 feels sluggish vs validation.
  double volatilityAdaptationRate = defaultVolatilityAdaptationRate;

  /// The surprise adaptation rate, i.e. γ from the paper.
  ///
  /// Interpretation: after the usual Kalman variance shrink
  /// V_i <- V_i * (1 - K_i), add extra variance when today's innovation is
  /// larger than the model expected: γ * max(0, e_i^2 - (V_i + σ_sport^2 + σ_i^2)).
  /// Stops V_i from monotonically collapsing to overconfidence (cf. basic Kalman).
  /// Does not replace β: β updates "typical miss size," γ widens rating uncertainty
  /// when a single observation is unexpectedly huge.
  ///
  /// Tuning: dimensionless, nonnegative. Typical band ~0.03--0.15.
  /// -> too small: little recovery from surprise bombs; ratings stay stiff.
  /// -> ~0.07: default balance for modest V_i bumps on outliers.
  /// -> too large: V_i can spike or oscillate after one odd match.
  double surpriseAdaptationRate = defaultSurpriseAdaptationRate;

  /// The pairwise blend weight, i.e. α from the paper.
  ///
  /// Interpretation: controls how much to blend pairwise residuals into
  /// the baseline-derived performance. The baseline performance is durable
  /// to differences in expected performance with the same sign as the model's
  /// expectations, but may in some cases lose information in the event that
  /// you lose to someone you shouldn't or beat someone you should.
  ///
  /// The observed performance is calculated as:
  /// P_i = L_i + B + α * D_i
  ///    - L_i is the log-score
  ///    - B is the baseline performance
  ///    - D_i is the pairwise residual
  ///    - α is the pairwise blend weight
  ///
  /// Tuning: dimensionless, nonnegative, most likely in [0, 1].
  /// -> 0: ignore pairwise residuals entirely.
  /// -> 1: pairwise residuals fully applied.
  /// -> > 1: pairwise residuals applied with additional emphasis.
  double pairwiseBlendWeight = defaultPairwiseBlendWeight;

  LatentLogSettings({
    this.byStage = false,
    this.scaleOffset = defaultScaleOffset,
    this.scaleFactor = defaultScaleFactor,
    this.sportVolatility = defaultSportVolatility,
    this.skillDriftRate = defaultSkillDriftRate,
    this.startingVariance = defaultStartingVariance,
    this.volatilityAdaptationRate = defaultVolatilityAdaptationRate,
    this.surpriseAdaptationRate = defaultSurpriseAdaptationRate,
    this.pairwiseBlendWeight = defaultPairwiseBlendWeight,
  });

  @override
  void encodeToJson(Map<String, dynamic> json) {
    json[_byStageKey] = byStage;
    json[_scaleOffsetKey] = scaleOffset;
    json[_scaleFactorKey] = scaleFactor;
    json[_sportVolatilityKey] = sportVolatility;
    json[_skillDriftRateKey] = skillDriftRate;
    json[_startingVarianceKey] = startingVariance;
    json[_volatilityAdaptationRateKey] = volatilityAdaptationRate;
    json[_surpriseAdaptationRateKey] = surpriseAdaptationRate;
    json[_pairwiseBlendWeightKey] = pairwiseBlendWeight;
  }

  @override
  void loadFromJson(Map<String, dynamic> json) {
    byStage = (json[_byStageKey] ?? false) as bool;
    scaleOffset = (json[_scaleOffsetKey] ?? defaultScaleOffset) as double;
    scaleFactor = (json[_scaleFactorKey] ?? defaultScaleFactor) as double;
    sportVolatility = (json[_sportVolatilityKey] ?? defaultSportVolatility) as double;
    skillDriftRate = (json[_skillDriftRateKey] ?? defaultSkillDriftRate) as double;
    startingVariance = (json[_startingVarianceKey] ?? defaultStartingVariance) as double;
    volatilityAdaptationRate = (json[_volatilityAdaptationRateKey] ?? defaultVolatilityAdaptationRate) as double;
    surpriseAdaptationRate = (json[_surpriseAdaptationRateKey] ?? defaultSurpriseAdaptationRate) as double;
    pairwiseBlendWeight = (json[_pairwiseBlendWeightKey] ?? defaultPairwiseBlendWeight) as double;
  }

}