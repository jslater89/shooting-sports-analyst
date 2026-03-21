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
  static const defaultMatchDifficultyVariance = 0.10;
  static const defaultTailNoiseStartPercent = 0.60;
  static const defaultTailNoiseVariance = 0.06;
  static const defaultBaselineRobustnessZ = 2.5;
  static const defaultWeakFieldVariance = 0.50;
  static const defaultWeakFieldMaxSize = 10.0;
  static const defaultWeakFieldWeakFinishThreshold = 0.60;
  static const defaultWeakFieldWeakFractionThreshold = 0.40;

  static const _byStageKey = "latentLogByStage";
  static const _scaleOffsetKey = "latentLogScaleOffset";
  static const _scaleFactorKey = "latentLogScaleFactor";
  static const _sportVolatilityKey = "latentLogSportVolatility";
  static const _skillDriftRateKey = "latentLogSkillDriftRate";
  static const _startingVarianceKey = "latentLogStartingVariance";
  static const _volatilityAdaptationRateKey =
      "latentLogVolatilityAdaptationRate";
  static const _surpriseAdaptationRateKey = "latentLogSurpriseAdaptationRate";
  static const _pairwiseBlendWeightKey = "latentLogPairwiseBlendWeight";
  static const _matchDifficultyVarianceKey = "latentLogMatchDifficultyVariance";
  static const _baselineRobustnessZKey = "latentLogBaselineRobustnessZ";
  static const _tailNoiseStartPercentKey = "latentLogTailNoiseStartPercent";
  static const _tailNoiseVarianceKey = "latentLogTailNoiseVariance";
  static const _weakFieldVarianceKey = "latentLogWeakFieldVariance";
  static const _weakFieldMaxSizeKey = "latentLogWeakFieldMaxSize";
  static const _weakFieldWeakFinishThresholdKey =
      "latentLogWeakFieldWeakFinishThreshold";
  static const _weakFieldWeakFractionThresholdKey =
      "latentLogWeakFieldWeakFractionThreshold";

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

  /// Robustness threshold for baseline residuals, measured in residual standard deviations.
  ///
  /// Interpretation: the match baseline is first estimated normally, then
  /// competitors whose residuals sit farther than this many sigmas from the
  /// field center are downweighted with a Huber-style taper. This reduces the
  /// leverage of extreme outliers when anchoring the field.
  ///
  /// Tuning: nonnegative.
  /// -> 0: disable baseline robustification.
  /// -> 2.0-2.5: strong outlier damping.
  /// -> 3.0+: lighter damping, closer to the raw weighted mean.
  double baselineRobustnessZ = defaultBaselineRobustnessZ;

  /// The finish percentage below which low finishes receive extra observation noise.
  ///
  /// Interpretation: match percentages above this threshold use the ordinary
  /// observation variance model. Below it, the system still uses raw log scores,
  /// but treats deep-tail results as less precise evidence.
  ///
  /// Tuning: ratio in (0, 1).
  /// -> 0.60: USPSA-oriented default; start inflating noise in the B-class-ish tail.
  /// -> 0.50: trust more of the field before tail noise begins.
  /// -> lower values: only the extreme tail receives extra noise.
  double tailNoiseStartPercent = defaultTailNoiseStartPercent;

  /// Maximum extra observation variance applied at the very bottom of the field.
  ///
  /// Interpretation: below [tailNoiseStartPercent], observation variance grows
  /// smoothly as finish percentage decreases. This preserves global log-linearity
  /// while downweighting weak deep-tail evidence in updates and baseline anchoring.
  ///
  /// Tuning: variance units, nonnegative.
  /// -> 0: disable tail-noise inflation.
  /// -> ~0.03: light damping of weak finishes.
  /// -> ~0.06: USPSA-oriented default; stronger damping of weak finishes.
  /// -> larger values: increasingly skeptical of very weak finishes.
  double tailNoiseVariance = defaultTailNoiseVariance;

  /// Match-level uncertainty added for highly degenerate weak fields.
  ///
  /// Interpretation: this is the maximum additional observation variance added
  /// when a field is both small and bottom-heavy, such as a 2-4 person field
  /// where many non-winners finish far below the winner. It is intended to
  /// suppress pathological update explosions without altering the raw log-score
  /// mean link.
  ///
  /// Tuning: variance units, nonnegative.
  /// -> 0: disable weak-field damping.
  /// -> ~0.10: light extra caution in degenerate fields.
  /// -> ~0.20-0.30: strong damping in clearly pathological tiny fields.
  /// -> ~0.50: very strong USPSA-oriented damping for tiny weak fields.
  double weakFieldVariance = defaultWeakFieldVariance;

  /// Field size at which weak-field damping decays to zero.
  ///
  /// Interpretation: two-person fields receive the full size penalty; fields at
  /// or above this size receive none. Values in between are interpolated
  /// smoothly.
  ///
  /// Tuning: > 2.
  /// -> 6: only very tiny fields are affected.
  /// -> 10: default; small fields remain meaningfully damped.
  /// -> larger values: allow some damping into bigger fields.
  double weakFieldMaxSize = defaultWeakFieldMaxSize;

  /// Finish threshold used to define a "weak" non-winning finish.
  ///
  /// Interpretation: non-winners below this ratio count toward a field being
  /// bottom-heavy. The farther below this threshold they are, the stronger the
  /// weak-field pathology signal becomes.
  ///
  /// Tuning: ratio in (0, 1).
  /// -> 0.40: only very poor finishes count as weak.
  /// -> 0.50: captures the "below half the winner" heuristic.
  /// -> 0.60: USPSA-oriented default; more fields trigger weak-field damping.
  double weakFieldWeakFinishThreshold = defaultWeakFieldWeakFinishThreshold;

  /// Fraction of non-winners that must be weak before weak-field damping activates.
  ///
  /// Interpretation: if the share of weak non-winners is below this threshold,
  /// no match-level pathology variance is added. Above it, the pathology term
  /// ramps up smoothly.
  ///
  /// Tuning: ratio in [0, 1).
  /// -> 0.33: more sensitive to scattered weak tails.
  /// -> 0.40: USPSA-oriented default; activates when weak finishes are common.
  /// -> 0.50: "about half the field below threshold" starts to matter.
  /// -> 0.67: only very bottom-heavy fields trigger.
  double weakFieldWeakFractionThreshold = defaultWeakFieldWeakFractionThreshold;

  /// The prior variance on match difficulty, i.e. τ² from the paper.
  ///
  /// Interpretation: how much match difficulty varies from one event to the
  /// next. Places a Bayesian prior B ~ N(0, τ²) on the match baseline,
  /// shrinking the baseline estimate toward zero (average difficulty) when
  /// the field is too small to reliably estimate it.
  ///
  /// The prior precision 1/τ² acts as a "virtual field weight." In a
  /// 2-person match, this dominates the single opponent's contribution,
  /// heavily damping the baseline. In a 100-person match, the field's
  /// total precision weight overwhelms the prior and it has negligible
  /// effect.
  ///
  /// In practice, this is best treated as a weak regularization knob rather
  /// than a literal claim about real-world match difficulty. Stronger values
  /// can flatten the entire rating scale by shrinking every baseline.
  ///
  /// Tuning: variance units, positive. Smaller values imply stronger
  /// shrinkage; larger values imply weaker shrinkage.
  /// -> 0.03: strong prior, roughly equivalent to one competitor of weight ~33.
  /// -> 0.10: moderate backstop for tiny fields.
  /// -> 0.25: very weak backstop.
  /// -> 0.10: weak default backstop.
  double matchDifficultyVariance = defaultMatchDifficultyVariance;

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
    this.baselineRobustnessZ = defaultBaselineRobustnessZ,
    this.tailNoiseStartPercent = defaultTailNoiseStartPercent,
    this.tailNoiseVariance = defaultTailNoiseVariance,
    this.weakFieldVariance = defaultWeakFieldVariance,
    this.weakFieldMaxSize = defaultWeakFieldMaxSize,
    this.weakFieldWeakFinishThreshold = defaultWeakFieldWeakFinishThreshold,
    this.weakFieldWeakFractionThreshold = defaultWeakFieldWeakFractionThreshold,
    this.matchDifficultyVariance = defaultMatchDifficultyVariance,
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
    json[_baselineRobustnessZKey] = baselineRobustnessZ;
    json[_tailNoiseStartPercentKey] = tailNoiseStartPercent;
    json[_tailNoiseVarianceKey] = tailNoiseVariance;
    json[_weakFieldVarianceKey] = weakFieldVariance;
    json[_weakFieldMaxSizeKey] = weakFieldMaxSize;
    json[_weakFieldWeakFinishThresholdKey] = weakFieldWeakFinishThreshold;
    json[_weakFieldWeakFractionThresholdKey] = weakFieldWeakFractionThreshold;
    json[_matchDifficultyVarianceKey] = matchDifficultyVariance;
  }

  @override
  void loadFromJson(Map<String, dynamic> json) {
    byStage = (json[_byStageKey] ?? false) as bool;
    scaleOffset = (json[_scaleOffsetKey] ?? defaultScaleOffset) as double;
    scaleFactor = (json[_scaleFactorKey] ?? defaultScaleFactor) as double;
    sportVolatility =
        (json[_sportVolatilityKey] ?? defaultSportVolatility) as double;
    skillDriftRate =
        (json[_skillDriftRateKey] ?? defaultSkillDriftRate) as double;
    startingVariance =
        (json[_startingVarianceKey] ?? defaultStartingVariance) as double;
    volatilityAdaptationRate =
        (json[_volatilityAdaptationRateKey] ?? defaultVolatilityAdaptationRate)
            as double;
    surpriseAdaptationRate =
        (json[_surpriseAdaptationRateKey] ?? defaultSurpriseAdaptationRate)
            as double;
    pairwiseBlendWeight =
        (json[_pairwiseBlendWeightKey] ?? defaultPairwiseBlendWeight) as double;
    baselineRobustnessZ =
        (json[_baselineRobustnessZKey] ?? defaultBaselineRobustnessZ) as double;
    tailNoiseStartPercent =
        (json[_tailNoiseStartPercentKey] ?? defaultTailNoiseStartPercent)
            as double;
    tailNoiseVariance =
        (json[_tailNoiseVarianceKey] ?? defaultTailNoiseVariance) as double;
    weakFieldVariance =
        (json[_weakFieldVarianceKey] ?? defaultWeakFieldVariance) as double;
    weakFieldMaxSize =
        (json[_weakFieldMaxSizeKey] ?? defaultWeakFieldMaxSize) as double;
    weakFieldWeakFinishThreshold =
        (json[_weakFieldWeakFinishThresholdKey] ??
                defaultWeakFieldWeakFinishThreshold)
            as double;
    weakFieldWeakFractionThreshold =
        (json[_weakFieldWeakFractionThresholdKey] ??
                defaultWeakFieldWeakFractionThreshold)
            as double;
    matchDifficultyVariance =
        (json[_matchDifficultyVarianceKey] ?? defaultMatchDifficultyVariance)
            as double;
  }
}
