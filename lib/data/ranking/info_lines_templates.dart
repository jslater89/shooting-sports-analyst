class InfoLinesTemplates {
  static const templatePrefix = "@tpl:";
  static InfoLinesTemplates _instance = InfoLinesTemplates._();

  Map<String, List<String>> _templates = {};

  factory InfoLinesTemplates() {
    return _instance;
  }

  InfoLinesTemplates._() {
    _templates["llrV1"] = _llrV1Template;
    _templates["eloV1"] = _eloV1Template;
    _templates["glickoV1"] = _glickoV1Template;
  }

  List<String>? getTemplateLines(String templateName) {
    return _templates[templateName];
  }
}

const _llrV1Template = [
  "Finish: {{finish}} of {{competitors}} at {{finishPercent}}%",
  "Rating ± Change: {{rating}}/{{change}}",
  "Momentum ± Change: {{momentum}}/{{momentumChange}}",
  "Trend vMod, λ_eff/c_i: {{momentumCorrection}}, {{lambdaEff}}/{{certainty}}",
  "Variance ± Change: {{variance}}/{{varianceChange}}",
  "Shock vMod, e_phys²/T_i: {{surpriseCorrection}}, {{ePhysSquared}}/{{totalNoise}} SV",
  "Dispersion ± Change: {{dispersion}}/{{dispersionChange}}",
  "Considered {{opponents}} opponents",
  "Global/local baseline: {{globalBaseline}}/{{localBaseline}}",
  "Own dispersion: {{ownDispersion}} SV",
  "Prior/obs/total: {{priorVariance}}/{{observationNoise}}/{{totalNoise}} SV → K={{kalmanGain}}",
  "Prior: aged {{ownVariance}} + trend {{trendInjection}} (drift {{timeVariance}}) SV",
  "Clean obs: sport 1.0 + disp {{effectiveDispersion}} + B {{baselineVar}} = {{cleanObsNoise}} SV",
  "Reliability: tail {{tailNoise}} + weak {{weakField}} + novel {{noveltyNoise}} (μ̄={{fieldMaturity}}) SV  Q={{obsQuality}}",
  "Baseline mix: α={{pairwiseAlpha}} → (1-α²){{globalBaselineNoise}} + α²{{localBaselineNoise}}",
  "z-score/damping: {{innovationZScore}}/{{weight}}x",
  "Raw/damped innovation: {{innovation}}/{{dampedInnovation}}",
  "Baseline residual/total weight: {{baselineResidual}}/{{totalWeight}}",
];

const _eloV1Template = [
  "Actual/expected percent: {{pcActual}}/{{pcExpected}} on {{stage}}",
  "Actual/expected place: {{placeActual}}/{{placeExpected}}",
  "Rating ± Change: {{rating}}/{{change}} ({{eloFromPct}} from pct, {{eloFromPlace}} from place)",
  "eff. K, multipliers: {{effK}}, SoS {{sos}}, IP {{ip}}, Zero {{zero}}",
  "Conn {{conn}}, EW {{ew}}, Err {{err}}, Dir {{dir}}, Bomb {{bomb}}",
];

const _glickoV1Template = [
  "Finish: {{finish}} of {{competitors}} at {{finishPercent}}%",
  "Rating ± Change: {{rating}}/{{change}}",
  "RD ± Change: {{rd}}/{{rdChange}}",
  "Volatility ± Change: {{volatility}}/{{volatilityChange}}",
  "Considered {{opponents}} opponents",
];