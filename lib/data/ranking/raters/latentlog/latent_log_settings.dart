/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math';

import 'package:shooting_sports_analyst/data/ranking/model/rating_settings.dart';

class LatentLogSettings extends RaterSettings {
  // Default scale generates roughly Elo-style numbers between 0 and 2000,
  // per Shooting Sports Analyst tradition.
  static const defaultScaleOffset = 1330.0;
  static const defaultScaleFactor = 1400.0;
  static const defaultStartingRating = 0.0;

  static const defaultSportVariance = 0.0012;
  static const defaultSkillDriftRate = 0.0005;
  static const defaultStartingVariance = 0.0300;
  static const defaultMaximumVariance = 0.0400;
  static const defaultStartingDispersion = 0.000120;
  static const defaultIntraclassCorrelation = 0.3;
  static const defaultDispersionAdaptationRate = 0.10;
  static const defaultMomentumAdaptationRate = 0.20;
  static const defaultSurpriseAdaptationRate = 0.10;
  static const defaultPairwiseBlendWeight = 0.10;
  static const defaultStudentTCutoffZ = 2.0;

  static const defaultBaselineRobustnessZ = 2.5;
  static const defaultTailNoiseStartPercent = 0.40;
  static const defaultTailNoiseVariance = 0.04;
  static const defaultWeakFieldVariance = 0.25;
  static const defaultWeakFieldMaxSize = 10.0;
  static const defaultWeakFieldWeakFinishThreshold = 0.60;
  static const defaultWeakFieldWeakFractionThreshold = 0.40;
  static const defaultGraphMaturityThreshold = 10.0;
  static const defaultNoveltyVariance = 0.006;

  static const defaultPredictionSportVariance = 0.0;
  static const defaultPredictionBehavioralDispersionKappa = 0.75;
  static const defaultMeanReversionGraceYears = 1.0;
  static const defaultMeanReversionDecayRate = 0.035;

  static const _byStageKey = "latentLogByStage";
  static const _scaleOffsetKey = "latentLogScaleOffset";
  static const _scaleFactorKey = "latentLogScaleFactor";
  static const _startingRatingKey = "latentLogStartingRating";
  static const _intraclassCorrelationKey = "latentLogIntraclassCorrelation";
  static const _sportVarianceKey = "latentLogSportVolatility";
  static const _skillDriftRateKey = "latentLogSkillDriftRate";
  static const _startingVarianceKey = "latentLogStartingVariance";
  static const _startingDispersionKey = "latentLogStartingDispersion";
  static const _maximumVarianceKey = "latentLogMaximumVariance";
  static const _dispersionAdaptationRateKey =
      "latentLogVolatilityAdaptationRate";
  static const _surpriseAdaptationRateKey = "latentLogSurpriseAdaptationRate";
  static const _momentumAdaptationRateKey = "latentLogMomentumAdaptationRate";
  static const _pairwiseBlendWeightKey = "latentLogPairwiseBlendWeight";
  static const _studentTCutoffZKey = "latentLogStudentTCutoffZ";
  static const _baselineRobustnessZKey = "latentLogBaselineRobustnessZ";
  static const _tailNoiseStartPercentKey = "latentLogTailNoiseStartPercent";
  static const _tailNoiseVarianceKey = "latentLogTailNoiseVariance";
  static const _weakFieldVarianceKey = "latentLogWeakFieldVariance";
  static const _weakFieldMaxSizeKey = "latentLogWeakFieldMaxSize";
  static const _weakFieldWeakFinishThresholdKey =
      "latentLogWeakFieldWeakFinishThreshold";
  static const _weakFieldWeakFractionThresholdKey =
      "latentLogWeakFieldWeakFractionThreshold";
  static const _graphMaturityThresholdKey = "latentLogGraphMaturityThreshold";
  static const _noveltyVarianceKey = "latentLogNoveltyVariance";
  static const _predictionSportVarianceKey =
      "latentLogPredictionSportVariance";
  static const _predictionBehavioralDispersionKappaKey =
      "latentLogPredictionBehavioralVolatilityKappa";
  static const _meanReversionGraceYearsKey = "latentLogMeanReversionGraceYears";
  static const _meanReversionDecayRateKey = "latentLogMeanReversionDecayRate";

  /// Whether to calculate ratings by stage (true) or by match (false).
  bool byStage;

  /// The scale offset for latent log ratio display units.
  double scaleOffset;

  /// The scale factor for latent log ratio display units.
  double scaleFactor;

  /// The global starting rating center in internal latent-log units.
  double startingRating;

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
  double sportVariance = defaultSportVariance;

  /// The skill drift rate in variance units per rating period, i.e. σ_drift^2 from the paper.
  ///
  /// Interpretation: the amount by which competitor variance increases over one
  /// rating period. How much wider 1SD gets over time. Rating periods are 30 days.
  ///
  /// Tuning: e.g. σ_drift should grow by ±5% over one year (1 rating period).
  /// -> delta-v per year = ln(1.10)^2 - ln(1.05)^2.
  ///      justification: 5% initial 1SD, 10% 1SD at the end of the year. change
  ///      in variance is the difference between initial_sigma^2 and final_sigma^2.
  /// -> 0.0091 - 0.0024 = 0.0067 (variance)
  /// -> 0.0067 / 12 = 0.000558 (variance per rating period)
  double skillDriftRate = defaultSkillDriftRate;

  /// The committed variance for brand-new competitors (prior width before any match).
  ///
  /// Should not exceed [maximumVariance]; the UI enforces that.
  ///
  /// Tuning: 3-4x sport volatility in log space/SD terms, not in variance units.
  ///
  /// sqrt(V_initial) = k * σ_sport
  /// -> V_initial = k^2 * σ_sport^2
  /// -> V_initial = 3^2 * 0.0024 = 0.0216
  /// -> V_initial = 4^2 * 0.0024 = 0.0384
  double startingVariance = defaultStartingVariance;

  /// Initial behavioral dispersion σ_i² for brand-new competitors (Kalman observation-noise component).
  ///
  /// Independent of [sportVariance]; tune in variance units. Scaled display uses √(σ_i²) × scale factor.
  double startingDispersion = defaultStartingDispersion;

  /// Upper bound on committed rating variance after Kalman updates and after
  /// time-based skill drift in [LatentLogRating.calculateCurrentVariance].
  ///
  /// Defaults to the same numeric value as [startingVariance] for backward
  /// compatibility; you can raise it to allow veterans to carry more epistemic
  /// uncertainty without widening the prior for new shooters.
  double maximumVariance = defaultMaximumVariance;

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
  double dispersionAdaptationRate = defaultDispersionAdaptationRate;

  /// Lower bound multiplier for certainty-weighted dispersion adaptation.
  ///
  /// Interpretation: dispersion adaptation uses max(momentumAdaptationRate, certainty)
  /// where certainty grows as committed variance shrinks toward zero. Higher values keep
  /// adaptation responsive even when uncertainty is high; lower values slow early-career
  /// dispersion movement.
  ///
  /// Tuning: dimensionless in [0, 1].
  double momentumAdaptationRate = defaultMomentumAdaptationRate;

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

  /// Student-t full-strength cutoff c_t, in innovation sigmas.
  ///
  /// Interpretation: the robust mean-update weight is
  /// w_t(z) = min(1, (ν + c_t^2) / (ν + z^2)). Innovations within c_t
  /// sigmas of the expected update receive full weight; beyond c_t they are
  /// downweighted with a heavy-tailed taper. Raising c_t widens the
  /// "believable innovation" band before outlier damping begins; lowering it
  /// pulls the taper in toward smaller surprises.
  ///
  /// Tuning: sigmas, nonnegative.
  /// -> 1.0: legacy behavior; taper begins immediately past 1σ.
  /// -> 2.0: default; typical matches pass through largely undamped.
  /// -> 3.0+: only extreme innovations are downweighted.
  double studentTCutoffZ = defaultStudentTCutoffZ;

  /// The intraclass correlation coefficient, i.e. ρ from the paper.
  ///
  /// Interpretation: the field average uncertainty is a regularization term that
  /// is added to the observation noise to prevent catastrophic certainty collapse
  /// in large, unestablished fields.
  ///
  /// Tuning: dimensionless, nonnegative.
  /// -> 0: disable field average uncertainty.
  double intraclassCorrelation = defaultIntraclassCorrelation;

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

  /// Match-count threshold k_max for full graph maturity.
  ///
  /// Interpretation: each competitor contributes a maturity fraction
  /// μ_i = min(1, k_i / k_max), where k_i is their match/stage history count.
  /// Small values mature cohorts quickly; larger values keep novelty penalties
  /// active for longer.
  ///
  /// Tuning: count-like scalar, positive.
  double graphMaturityThreshold = defaultGraphMaturityThreshold;

  /// Maximum novelty variance ψ² applied to topologically isolated fields.
  ///
  /// Interpretation: match-level variance penalty that scales by field novelty
  /// (1 - \bar{μ}), where \bar{μ} is precision-weighted field maturity.
  /// Zero disables novelty damping.
  ///
  /// Tuning: variance units, nonnegative.
  double noveltyVariance = defaultNoveltyVariance;

  /// The idiosyncratic per-competitor sport noise used for prediction bands,
  /// in variance units.
  ///
  /// The full [sportVariance] includes both common-mode match difficulty
  /// (conditions that affect the entire field similarly) and idiosyncratic
  /// per-competitor noise (individual stumbles, concentration lapses, lucky
  /// runs). In relative predictions (competitor's percentage of the winner),
  /// the common-mode component cancels out — a harder match penalizes
  /// everyone proportionally. Only the idiosyncratic fraction survives into
  /// the prediction band.
  ///
  /// This parameter controls how much sport noise enters the predictive
  /// variance. It does not affect the update rule, which continues to use
  /// [sportVariance].
  ///
  /// Tuning: variance units, nonnegative, at most [sportVariance].
  /// -> 0: predictions use no sport noise (band reflects only rating uncertainty).
  /// -> ~0.0012: default; roughly half of σ²_sport, implying that about half
  ///    of match-to-match noise is common-mode difficulty.
  /// -> sportVariance: all sport noise is idiosyncratic (prediction band
  ///    matches the full observation model).
  double predictionSportVariance = defaultPredictionSportVariance;

  /// Fraction of behavioral variance (sigma_i^2) that enters predictive bands,
  /// in addition to rating variance V_i and prediction sport variance.
  ///
  /// The rating update still uses full behavioral variance in observation noise; kappa
  /// only scales how much of it counts toward posterior-predictive spread. Zero recovers
  /// bands that ignore behavioral volatility.
  ///
  /// Tuning: dimensionless, nonnegative; typical range 0 to 1.
  double predictionBehavioralDispersionKappa =
      defaultPredictionBehavioralDispersionKappa;

  /// Mean-reversion grace period, in years, before rating decay begins.
  ///
  /// Interpretation: elapsed inactivity shorter than this value contributes no
  /// rust decay. Intended to avoid penalizing normal off-season breaks.
  ///
  /// Tuning: years, nonnegative.
  /// -> 0.0: decay applies immediately.
  /// -> 0.5: approximately one half-year grace period.
  /// -> 1.0: approximately one full-year grace period.
  double meanReversionGraceYears = defaultMeanReversionGraceYears;

  /// Mean-reversion decay coefficient λ_rust, in inverse years.
  ///
  /// Interpretation: after grace time is exhausted, rating distance from the
  /// baseline decays as exp(-λ_rust * Δt_eff). Larger values imply faster
  /// reversion toward baseline during inactivity.
  ///
  /// Tuning: 1/years, nonnegative.
  /// -> 0.0: disable rust decay.
  /// -> 0.03: approximately 3% decay per year of post-grace inactivity.
  /// -> 0.10: aggressive long-gap decay.
  double meanReversionDecayRate = defaultMeanReversionDecayRate;

  int decimalCount() {
    final controllingParameter = max(scaleFactor, scaleOffset);
    if(controllingParameter >= 1000) {
        return 0;
    }
    else if(controllingParameter >= 100) {
        return 1;
    }
    else if(controllingParameter >= 10) {
        return 2;
    }
    else {
        return 3;
    }
  }

  String formatNumericRating(double rating) {
    final decimals = decimalCount();
    return (rating * scaleFactor + scaleOffset).toStringAsFixed(decimals);
  }

  String formatNumericRatingChange(double ratingChange) {
    final decimals = decimalCount() + 1;
    return (ratingChange * scaleFactor).toStringAsFixed(decimals);
  }

  LatentLogSettings({
    this.byStage = false,
    this.scaleOffset = defaultScaleOffset,
    this.scaleFactor = defaultScaleFactor,
    this.startingRating = defaultStartingRating,
    this.sportVariance = defaultSportVariance,
    this.skillDriftRate = defaultSkillDriftRate,
    this.startingVariance = defaultStartingVariance,
    this.startingDispersion = defaultStartingDispersion,
    this.maximumVariance = defaultMaximumVariance,
    this.dispersionAdaptationRate = defaultDispersionAdaptationRate,
    this.momentumAdaptationRate = defaultMomentumAdaptationRate,
    this.surpriseAdaptationRate = defaultSurpriseAdaptationRate,
    this.pairwiseBlendWeight = defaultPairwiseBlendWeight,
    this.studentTCutoffZ = defaultStudentTCutoffZ,
    this.baselineRobustnessZ = defaultBaselineRobustnessZ,
    this.intraclassCorrelation = defaultIntraclassCorrelation,
    this.tailNoiseStartPercent = defaultTailNoiseStartPercent,
    this.tailNoiseVariance = defaultTailNoiseVariance,
    this.weakFieldVariance = defaultWeakFieldVariance,
    this.weakFieldMaxSize = defaultWeakFieldMaxSize,
    this.weakFieldWeakFinishThreshold = defaultWeakFieldWeakFinishThreshold,
    this.weakFieldWeakFractionThreshold = defaultWeakFieldWeakFractionThreshold,
    this.graphMaturityThreshold = defaultGraphMaturityThreshold,
    this.noveltyVariance = defaultNoveltyVariance,
    this.predictionSportVariance = defaultPredictionSportVariance,
    this.predictionBehavioralDispersionKappa =
        defaultPredictionBehavioralDispersionKappa,
    this.meanReversionGraceYears = defaultMeanReversionGraceYears,
    this.meanReversionDecayRate = defaultMeanReversionDecayRate,
  });

  @override
  void encodeToJson(Map<String, dynamic> json) {
    json[_byStageKey] = byStage;
    json[_scaleOffsetKey] = scaleOffset;
    json[_scaleFactorKey] = scaleFactor;
    json[_startingRatingKey] = startingRating;
    json[_sportVarianceKey] = sportVariance;
    json[_skillDriftRateKey] = skillDriftRate;
    json[_startingVarianceKey] = startingVariance;
    json[_startingDispersionKey] = startingDispersion;
    json[_maximumVarianceKey] = maximumVariance;
    json[_intraclassCorrelationKey] = intraclassCorrelation;
    json[_dispersionAdaptationRateKey] = dispersionAdaptationRate;
    json[_momentumAdaptationRateKey] = momentumAdaptationRate;
    json[_surpriseAdaptationRateKey] = surpriseAdaptationRate;
    json[_pairwiseBlendWeightKey] = pairwiseBlendWeight;
    json[_studentTCutoffZKey] = studentTCutoffZ;
    json[_baselineRobustnessZKey] = baselineRobustnessZ;
    json[_tailNoiseStartPercentKey] = tailNoiseStartPercent;
    json[_tailNoiseVarianceKey] = tailNoiseVariance;
    json[_weakFieldVarianceKey] = weakFieldVariance;
    json[_weakFieldMaxSizeKey] = weakFieldMaxSize;
    json[_weakFieldWeakFinishThresholdKey] = weakFieldWeakFinishThreshold;
    json[_weakFieldWeakFractionThresholdKey] = weakFieldWeakFractionThreshold;
    json[_graphMaturityThresholdKey] = graphMaturityThreshold;
    json[_noveltyVarianceKey] = noveltyVariance;
    json[_predictionSportVarianceKey] = predictionSportVariance;
    json[_predictionBehavioralDispersionKappaKey] =
        predictionBehavioralDispersionKappa;
    json[_meanReversionGraceYearsKey] = meanReversionGraceYears;
    json[_meanReversionDecayRateKey] = meanReversionDecayRate;
  }

  @override
  void loadFromJson(Map<String, dynamic> json) {
    byStage = (json[_byStageKey] ?? false) as bool;
    scaleOffset = (json[_scaleOffsetKey] ?? defaultScaleOffset) as double;
    scaleFactor = (json[_scaleFactorKey] ?? defaultScaleFactor) as double;
    startingRating =
        (json[_startingRatingKey] ?? json["latentLogStarting"] ?? defaultStartingRating) as double;
    sportVariance =
        (json[_sportVarianceKey] ?? defaultSportVariance) as double;
    skillDriftRate =
        (json[_skillDriftRateKey] ?? defaultSkillDriftRate) as double;
    startingVariance =
        (json[_startingVarianceKey] ?? defaultStartingVariance) as double;
    startingDispersion = (json[_startingDispersionKey] as double?) ??
        (0.1 * sportVariance);
    maximumVariance = (json[_maximumVarianceKey] ??
            json[_startingVarianceKey] ??
            defaultMaximumVariance)
        as double;
    if (maximumVariance < startingVariance) {
      maximumVariance = startingVariance;
    }
    intraclassCorrelation =
        (json[_intraclassCorrelationKey] ?? defaultIntraclassCorrelation)
            as double;
    dispersionAdaptationRate =
        (json[_dispersionAdaptationRateKey] ?? defaultDispersionAdaptationRate)
            as double;
    momentumAdaptationRate =
        (json[_momentumAdaptationRateKey] ?? defaultMomentumAdaptationRate)
            as double;
    surpriseAdaptationRate =
        (json[_surpriseAdaptationRateKey] ?? defaultSurpriseAdaptationRate)
            as double;
    pairwiseBlendWeight =
        (json[_pairwiseBlendWeightKey] ?? defaultPairwiseBlendWeight) as double;
    studentTCutoffZ =
        (json[_studentTCutoffZKey] ?? defaultStudentTCutoffZ) as double;
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
    graphMaturityThreshold =
        (json[_graphMaturityThresholdKey] ?? defaultGraphMaturityThreshold)
            as double;
    noveltyVariance =
        (json[_noveltyVarianceKey] ?? defaultNoveltyVariance) as double;
    predictionSportVariance =
        (json[_predictionSportVarianceKey] ?? defaultPredictionSportVariance)
            as double;
    predictionBehavioralDispersionKappa =
        (json[_predictionBehavioralDispersionKappaKey] ??
                defaultPredictionBehavioralDispersionKappa)
            as double;
    meanReversionGraceYears =
        (json[_meanReversionGraceYearsKey] ?? defaultMeanReversionGraceYears)
            as double;
    meanReversionDecayRate =
        (json[_meanReversionDecayRateKey] ?? defaultMeanReversionDecayRate)
            as double;
  }
}
