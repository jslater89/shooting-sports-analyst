# LLR Hand-Sweep Tuning Plan

Working document. Written before play-money feedback is available, to be
revised once market signal arrives. Primary focus is CRPS on the top 40% of
predicted-rank buckets (top 20% + 20–40%), since that's where most user
interest concentrates and where we can still meaningfully evaluate outcomes.
Super-elite dominance cases (e.g. CS/ML at Nationals) are not evaluated
directly because ground truth for their win probabilities is too small-N
to validate against.

## Current Operating Point

From the most recent tuning run ("surprise adaptation 0.200"):

- `surpriseAdaptationRate` (γ): 0.200
- `predictionBehavioralDispersionKappa` (κ): 0.600 (predict-time only)
- Predictive-time sport-variance add-back: 0
- Student-t cutoff: 2σ (kept for leaderboard responsiveness, not CRPS)

Observed on validation (rated-only, n=2953), with the *top-40%* aggregate
computed as the n-weighted average of the top-20 and 20–40 buckets:

- Overall MAPE 8.29%, overall CRPS 0.0355
- Top-20 CRPS 0.0308 (1σ 73.5%, 2σ 95.0%)
- 20–40 CRPS 0.0321 (1σ 66.8%, 2σ 93.1%)
- Top-40 aggregate CRPS ≈ 0.0315 (n≈1159)
- Bottom-20 CRPS 0.0409 (1σ 49.7%, 2σ 79.2%) — informational only

Top-40 coverage is close to ideal (roughly 70 / 94 on the aggregate); the
sharpness-vs-coverage tension from earlier runs mostly bites the bottom
buckets, which we are deliberately de-prioritizing.

## Objectives (Ranked)

1. **Minimize top-40% CRPS** (n-weighted over top-20 and 20–40 buckets).
2. **Preserve top-40% coverage** within roughly ideal bands (1σ 65–75%,
   2σ 92–97%). Don't buy CRPS by flagrantly degrading calibration.
3. **Don't regress overall CRPS materially** (≤2% above current 0.0355).
   Keeps us honest that we're not over-fitting to the top-40 subset.
4. **Produce dated CSV + params artifacts** for later comparison once
   play-money data is flowing.

Explicitly **not** objectives:

- Super-elite dominance odds (CS/ML specific cases). No ground truth.
- Bottom-20 coverage. Likely partly structural; deferred.
- Minimize overall CRPS at all costs. Already in diminishing-returns
  territory across the last several runs.

## Metrics And Guardrails

| Metric                   | Target / Guardrail       | Role                      |
| ------------------------ | ------------------------ | ------------------------- |
| Top-40% CRPS (rated-only)| Minimize                 | Primary objective         |
| Top-40% 1σ coverage      | 65–75% (soft band)       | Calibration guardrail     |
| Top-40% 2σ coverage      | 92–97% (soft band)       | Calibration guardrail     |
| Overall CRPS (rated-only)| ≤ 0.0362 (2% guardrail)  | Reject on material regress|
| Bottom-20 CRPS / coverage| Informational only       | Monitor for collapse      |

Soft bands are for sanity-checking, not optimization. If a config improves
top-40 CRPS by a meaningful amount but lands just outside the coverage
band, keep it and note it — don't mechanically reject.

## Parameters, Priority Order

Reordered for a top-40% primary objective. High-certainty shooters have
c_i ≈ 1 and small momentum, so the parameters that most directly affect
their predicted distributions are the ones tightening or loosening their
filter dynamics, not the downstream prediction-time scalars.

1. **`surpriseAdaptationRate` (γ)**: 0.15, 0.20, 0.25, 0.30. Scales Trend
   and Shock injections at filter-time. High-certainty shooters'
   posteriors are mostly set by Kalman compression, so γ's effect on
   their predicted distributions is indirect but cumulative — this is
   the main tuning knob for top-end responsiveness.
2. **`momentumAdaptationRate` (λ)**: current, ±30%. Structurally stronger
   post-λ_eff change and not retuned since. λ_eff ≈ λ for top-certainty
   shooters, so this directly paces their Trend detection and feeds into
   the Kalman gain through the prior inflation path.
3. **Predictive-SV add-back**: zero, 25%, 50% σ²_sport. Predict-time
   additive floor. Expect zero to remain best for top-40 CRPS (adding a
   fixed variance disproportionately widens already-tight predicted
   distributions for shooters whose true predictive variance is small),
   but run it to confirm the sign.
4. **κ (`predictionBehavioralDispersionKappa`)**: 0.5, 0.6, 0.7.
   *Prediction-time only.* Scales how much of each shooter's committed
   dispersion $\tilde{\sigma}^2$ projects into predictive uncertainty.
   Does not affect filter dynamics, ratings, or committed variance —
   two configs with identical everything else but different κ will
   produce identical ratings and differ only in predictive width. For
   top-40 shooters whose dispersion is already small, κ's absolute
   effect on predictive variance is proportionally smaller than for
   lower-rated shooters, so expect modest movement here.
5. **`dispersionAdaptationRate`**: current, 2×. Diagnostic — does faster
   aleatoric adaptation change anything in the top-40, or is dispersion's
   slow EMA effectively quiescent for established shooters?

## Sweep Structure

### Phase 0: Determinism Floor (2 runs, ~6 min)

Run the current config twice. Measure CRPS / coverage delta between
identical runs on both overall and top-40 aggregates. This is the noise
floor; treat smaller differences as meaningless.

### Phase 1: 1D Coordinate Descent (~12 runs, ~35 min)

One parameter at a time, 3 points each (current, low, high), others held
at the running best. After each parameter, update the baseline to the
best-so-far (measured on top-40 CRPS) before moving on. Stop a sweep
early if movement is within the Phase 0 floor.

Before each run, write down the expected direction of top-40 CRPS and
coverage. A surprise is a learning event; an expected result is just
confirmation.

### Phase 2: 2×2 Factorial, γ × λ (~4 runs, ~12 min)

These are the two filter-time parameters most likely to have a genuine
structural interaction: λ sets the momentum EMA rate (and thus Trend
responsiveness via λ_eff in the denominator), while γ sets how much the
resulting Trend signal inflates the prior. Their combined effect on
top-end filter dynamics isn't easily decomposable into two independent
1D slices. Run the factorial around the Phase 1 winner. If Phase 1
produced no movement, run it around the current operating point — it
may surface an interaction the 1D sweeps missed.

If the κ 1D sweep in Phase 1 produced any movement on top-40 CRPS,
consider a γ × κ factorial as well. The interaction there is weaker —
causal-chain (γ changes committed dispersion; κ scales it at predict
time), not structural — but worth running if κ turned out to matter at
all. Budget permitting.

### Phase 3 (Optional): Fine Sweep Around Winner (~4 runs, ~12 min)

Only if Phase 2 identifies a clear winner and there's still budget:
sweep the top-contributing parameter in 2 finer steps around the winning
value. Skip this if Phase 1+2 produced flat results — that's your signal
to stop.

**Total budget**: ~18 runs, ~55 min wall time. Phase 3 optional.

## Process Notes

- CSV + params JSON are written per run (see `backtest_raters_command.dart`).
  Each run is self-describing; don't rely on terminal output alone.
- Maintain a running summary table (separate file, scratch pad, whatever)
  with params + top-40 CRPS + top-40 1σ/2σ + overall CRPS. This is the
  quick-decision view; full CSV is for retrospective analysis.
- The top-40 aggregate CRPS isn't emitted directly by the backtest
  command yet — compute it by hand from the two bucket rows in the CSV,
  n-weighted:
  `crps_top40 = (n_top20 * crps_top20 + n_q2 * crps_q2) / (n_top20 + n_q2)`
- Subset runs (if feasible): if the backtest command supports a smaller
  window, use it for screening and full runs only to validate promising
  configs. Accept that subset rankings correlate ~0.7–0.8 with full-data
  rankings — enough to screen, not enough to pick.

## Stopping Criteria

Stop before exhausting the plan if any of these happen:

- Two consecutive parameter sweeps produce no top-40 CRPS movement
  beyond the Phase 0 floor.
- Overall CRPS blows through the 2% guardrail; back out that parameter
  and reassess whether the objective ordering still makes sense.
- Top-40 coverage drifts significantly outside its band (>5 points on
  either side), suggesting the new operating point is trading
  calibration for sharpness in a way you haven't endorsed.

Definitely stop once:

- Phase 2 completes (or Phase 3, if run) and a winner is chosen, **or**
- Play-money feedback begins. At that point this plan is superseded by a
  market-informed one.

## Counterpoints To Self

- Choosing top-40% CRPS as the objective tacitly assumes high-certainty
  shooters' predictive errors are what matters for user value. That's
  probably true for the "who's going to win" question, but the right
  measure might actually be top-40% calibration — i.e., coverage —
  rather than CRPS. If CRPS improves but coverage degrades, you may be
  making odds sharper without making them more honest. The guardrail
  bands hedge against this, but they're just bands; keep an eye on the
  interaction.
- The top-40 aggregate smooths out the distinct personalities of the
  top-20 and 20–40 buckets. A config that improves one substantially
  while degrading the other by a similar amount will look flat on the
  aggregate. Watch the two bucket rows separately, not just the
  aggregate, when a run produces a suspiciously small movement.
- We're likely to find ≤3% top-40 CRPS improvement. If so, that's still
  a real (if modest) result, but at that size the gains are likely
  inside normal sampling noise even with n≈1159. A bootstrap CI on
  top-40 CRPS for the current and winning configs would be worth running
  before declaring victory.
- If top-40 coverage starts degrading during Phase 1 (falling below the
  soft band rather than just drifting), reconsider the order: predictive-SV
  and κ are both predict-time knobs that widen distributions without
  touching filter dynamics, so either one can restore coverage
  surgically if the filter-time sweeps take us too sharp. Predictive-SV
  adds a flat floor; κ multiplicatively scales dispersion. Pick whichever
  has more slope in the 1D sweep.
- The priority list leans on one structural claim: that top-40 shooters
  have small dispersion, so κ's effect is proportionally small. This
  is true in steady state but can break down for a top-end shooter who's
  momentarily dispersion-high (e.g., just returning from a layoff). If
  you see κ sensitivity that the priority order didn't predict, that's
  probably why — not a bug in the plan so much as the priority
  capturing typical rather than worst-case behavior.

## Deferred (Post-Play-Money)

Structural items the hand sweep will not address. Documented so they
aren't forgotten:

- **Inverse heteroscedasticity in log-space**: residual variance is
  tighter at the top, wider at the bottom. With top-40 as the primary
  objective, this is mostly a bottom-bucket problem, so deferring it is
  even more defensible now. Dispersion captures the idea but its EMA is
  too slow to follow rating trajectories.
- **Candidate remedies** (not yet implemented):
  - Predict-time rating-conditional multiplier $f(R)$ on predictive σ².
    Cheapest test of "is rating-conditional correction worth it?"
    Reversible, doesn't touch filter dynamics.
  - Two-component dispersion: structural $f(R)$ + per-shooter
    idiosyncratic EMA. Cleaner decomposition but a bigger lift.
- **When to revisit**: once play-money feedback reveals whether the
  largest source of market-relevant error is (a) mid-pack calibration
  that would benefit from $f(R)$, (b) bottom-bucket odds that aren't
  actively traded anyway, or (c) something this plan never addressed.
