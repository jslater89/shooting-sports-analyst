/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "package:shooting_sports_analyst/data/help/entries/latent_log_help.dart";
import "package:shooting_sports_analyst/data/help/help_topic.dart";

const latentLogConfigHelpId = "latentLog_config";
const latentLogConfigHelpLink = "?latentLog_config";
final helpLatentLogConfig = HelpTopic(
  id: latentLogConfigHelpId,
  name: "Latent log ratio configuration",
  content: _content,
);

const _content =
"""# Latent Log Ratio Configuration

The latent log ratio rating system can be fine-tuned through many parameters. This guide
explains each setting and its effects. For general information on the LLR rating system, see
the [Latent log ratio help entry]($latentLogHelpLink).

Most variance-related parameters are stored in internal (log-space) variance units. The
configuration UI shows both internal values and a scaled column. For variance fields, the
scaled column expresses the value in units of sport variance (SV) or, for sport variance
itself, as a very approximate ±% finish equivalent. Dimensionless adaptation rates (β, γ, λ, α,
ρ, κ, and the Student-t parameters) are edited as a single value each.

### Scaling Parameters

Scale offset is added after multiplying the internal rating by the scale factor:
`display = internal × scale factor + offset`. The default offset of 100 places a typical field
center around 100 display points. Note that "center" more correctly means something like "center
of gravity" here. For USPSA major match fields, since most finishers are above 50% at most majors,
LLR produces a distinct hump on the right side of the graph with a longer left tail.

Scale factor converts internal log units to display points. It also rescales variance and
dispersion on rating rows: internal variance is multiplied by scale factor squared for
display. Changing the scale factor immediately updates the scaled column for variance fields
without changing their internal values.

Starting/central rating is the global center for new competitors and the target of mean
reversion during long inactivity, expressed in internal units.

### Core Parameters

Sport variance is the mostly irreducible variance of the sport — how much ln(finish) wiggles
around true skill from match to match for a consistent competitor. All observation noise models
and several scaled-column displays are normalized against this value. Tuning guide: a ±5%
one-standard-deviation swing in finish percentage corresponds to roughly ln(1.05)² ≈ 0.0024 in
variance units. For predictions that are more resistent to outliers, use larger sport variance
while holding the other parameters constant. For predictions that follow recent match results
more closely, use smaller sport variance.

Skill drift / period is the amount by which committed variance grows per year of inactivity
(from the last rating update). Rating periods are 365 days. This represents widening
uncertainty over time, not movement of the rating itself (that is mean reversion).

Starting variance is the committed prior width for brand-new competitors. It should be wider
than sport variance — typically 3-4× in standard-deviation terms. Must not exceed maximum
variance.

Maximum variance caps committed variance after Kalman updates and after time-based skill drift.
It can exceed starting variance so veterans may carry more epistemic uncertainty than the
new-shooter prior without widening the prior for everyone. Given standard settings, this value
rarely comes into play.

Starting dispersion σ_i² is the initial per-competitor behavioral volatility for new shooters.
Dispersion is the excess volatility in competitor scores after accounting for sport variance
and trend. Realized values in rating data are often small compared to variance.
It feeds the observation-noise component of the Kalman filter independently of sport variance.
The scaled column shows the value in sport-variance units.

Intraclass correlation ρ is a dimensionless regularization term added to baseline uncertainty
estimates. It prevents the system from incorrectly assuming that a large field of poorly-known
competitors can produce a completely valid skill estimate. Set to 0 to disable.

### Adaptation Rates

Dispersion adaptation β controls how quickly per-competitor dispersion tracks recent squared
innovations. Dispersion is an exponential moving average: σ_i² ← (1 − β) σ_i² + β e_i². High
β reacts quickly to one wild match; low β smooths over many events. Typical range: 0.05-0.20.

Momentum adaptation rate λ is the smoothing factor for the momentum exponential moving average.
Momentum tracks sustained directional drift in innovations. When momentum is large, the system
injects extra prior variance before the Kalman update (trend injection), allowing ratings to
follow a run of form more quickly. The effective adaptation rate is scaled by rating certainty,
so early-career competitors with wide priors adapt more slowly.

Surprise adaptation γ adds extra committed variance when a single observation is unexpectedly
large — beyond what the model's total noise predicted. This prevents variance from
monotonically collapsing to overconfidence. It complements β: β updates typical miss size, γ
widens rating uncertainty on outliers. Typical range: 0.03–0.15.

Pairwise blend α controls how much pairwise residuals contribute to observed performance:
P = L + (1-α)B + αD, where L is the log score, B is the baseline, and D is the pairwise residual.
At 0, pairwise information is ignored entirely. At 1, it is used exclusively.

### Student-t Robustness

Student-t ν is the degrees-of-freedom parameter for innovation downweighting. Innovations
beyond a cutoff distance (in sigmas) are damped with a heavy-tailed taper:
w = min(1, (ν + c²) / (ν + z²)). Lower ν damps more aggressively.

Student-t cutoff c_t (positive) is the innovation sigma distance below which positive
innovations receive full weight. Positive surprises are treated as more likely to reflect real
skill changes, so the positive cutoff is typically wider than the negative one.

Student-t cutoff c_t (negative) is the corresponding cutoff for negative innovations. Tighter
values downweight bad stages more aggressively—useful when equipment failures and other
non-skill factors dominate large negative surprises.

### Small and Degenerate Field Parameters

Baseline robustness z applies a Huber-style taper to baseline weights. Competitors whose
residuals sit farther than this many sigmas from the field center contribute less to the
baseline anchor. Set to 0 to disable. Values around 2.0-2.5 provide strong outlier damping.

Tail noise start % is the finish percentage below which deep-tail results receive extra
observation noise. Finishes above this threshold use the ordinary variance model. The default
of 0.60 is USPSA-oriented: tail noise begins around B-class territory.

Tail noise variance is the maximum extra observation variance applied at the very bottom of the
field. Below the start threshold, noise grows smoothly as finish percentage decreases. Set to
0 to disable.

Weak-field variance is the maximum additional match-level observation noise for tiny,
bottom-heavy fields: the classic two-to-four person local or poorly-attended major in a division
where most non-winners finish far below the winner. Set to 0 to disable.

Weak-field max size is the field size at which weak-field damping shuts off completely.
Two-person fields receive the full size penalty; fields at or above this size receive none.

Weak finish threshold defines a "weak" non-winning finish. Non-winners below this ratio count
toward detecting a bottom-heavy field. 0.50 corresponds to a finish percentage of 50%.

Weak fraction threshold is the minimum fraction of non-winners that must be weak before
weak-field damping activates. At 0.60, three fifths of non-winners must be below the
weak-finish threshold.

Graph maturity threshold k_max is the experience count in events (matches, or stages in by-stage
mode) at which a competitor is treated as fully mature for novelty weighting. Each competitor
contributes a logarithmic maturity fraction; field maturity is the precision-weighted mean.
Novelty variance scales by (1 - field maturity). Smaller values mature cohorts quickly; larger
values keep novelty penalties active longer.

Novelty variance ψ² is the maximum topological-isolation variance penalty for immature fields.
Set to 0 to disable.

### Prediction Parameters

Prediction sport σ² is the idiosyncratic per-competitor sport noise used in prediction bands.
The full sport variance includes both common-mode match difficulty (which affects the entire
field similarly) and idiosyncratic noise. In relative percentage predictions, common-mode
difficulty cancels out — a harder match penalizes everyone proportionally. Only the
idiosyncratic fraction survives into the band. This parameter does not affect rating updates.

Prediction behavioral κ is the fraction of behavioral variance (σ_i²) that enters predictive
bands, in addition to rating variance and prediction sport variance. The update rule still
uses full σ_i² in observation noise; κ only scales how much of it counts toward
posterior-predictive spread. Set to 0 to ignore behavioral volatility in bands.

### Mean Reversion

Grace period t_grace is the number of years of inactivity before chronological mean-reversion
decay begins. Intended to avoid penalizing normal off-season breaks. Set to 0 for immediate
decay.

Rust decay λ_rust is the exponential decay coefficient applied to rating distance from the
central rating after the grace period is exhausted. Rating reverts as:
center + (rating − center) × exp(−λ_rust × effective inactive years). Set to 0 to disable.

### By Stage

When enabled, each stage is a separate rating update. When disabled, the whole match is one
update (stages are still counted for experience). By-match is recommended; by-stage produces
much more volatile ratings when using by-match settings.""";
