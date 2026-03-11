# Bayesian Odds Adjustment for Prediction Game

## Overview

This document describes a Bayesian approach for adjusting betting odds based on player wagering activity, designed for the sparse liquidity environment of practical shooting sports betting.

## The Core Problem

In traditional sports betting, odds follow the money through simple supply/demand mechanics. With millions of dollars wagered, markets self-correct through liquidity. However, in practical shooting:

- **Low liquidity**: Few bets per specific market
- **Fragmented markets**: Hundreds of possible markets (any shooter, any place range, any percentage)
- **No exact market matching**: "Max Michel 1st-3rd" vs "Max Michel 1st-5th" are similar but distinct
- **Information signals**: Each bet carries information about the true probability

**Solution**: Use Bayesian updating to treat each bet as evidence that updates our probability estimates in a principled way. When generating odds for a new prediction, the system:

1. **Gathers related wagers.** Find all previously accepted bets on the same shooter and market type (place or percentage). Spread bets are decomposed into percentage signals for each involved shooter. Each wager is treated independently — no aggregation by market predicate.
2. **Computes a posterior for each wager.** Each wager has a raw weight (based on conviction, bettor skill, and timing). When cross-market evidence is clustered (e.g. several bets on similar place ranges or nearby percentage thresholds), a similarity calculation adds effective weight so that probability density is reflected. The prior α for that wager comes from the Monte Carlo model probability × N_eff; the wager's effective weight (raw + similarity-derived) is added to α, giving a posterior probability per wager.
3. **Finds a distribution shift (δ).** Search for the single δ that, when applied to all Monte Carlo trial results for this shooter, best fits the posteriors across all wagers simultaneously (weighted least squares using each wager's **raw** weight). This δ represents "bets say this shooter is about δ units better/worse than the model thinks," where 'units' are places or percentage points, depending on market type.
4. **Evaluates the requested prediction under the shifted distribution.** Shift every MC sample by δ, count how many satisfy the requested market's predicate, and derive the adjusted probability. Apply the house edge to produce final odds.

A bet on one market (e.g. "1st-10th") naturally moves the odds for every related market (e.g. "1st-5th", "12th-16th") — correctly, with the right magnitude and direction — because they all share the same δ.

## Mathematical Foundation

### Beta Distribution for Probability Estimates

We model our uncertainty about probabilities using a Beta distribution:

```
P(outcome) ~ Beta(α, β)
```

Where:

- **α** = "successes" or evidence the event occurs
- **β** = "failures" or evidence the event doesn't occur
- **Mean probability** = α / (α + β)
- **Total confidence** = α + β (higher = more confident)

#### Example: Model Confidence

If our Monte Carlo simulation predicts P = 0.65 for "Max Michel finishes 1st-3rd":

**High confidence** (tested on 100 similar predictions, 65 correct):

```
α = 65, β = 35
Mean = 65/100 = 0.65
Confidence = 100 (high)
```

**Low confidence** (tested on 10 similar predictions, 6.5 correct):

```
α = 6.5, β = 3.5
Mean = 6.5/10 = 0.65
Confidence = 10 (low)
```

The low-confidence estimate will move more when new evidence (bets) arrives.

### Principled Setting of α and β

Beyond tuning α and β by trial and error, we can tie them to the model and data:

**1. Effective sample size.** Set α = P×N_eff and β = (1−P)×N_eff so the prior has mean P and "as much weight as N_eff observations." The Monte Carlo runs 10,000 trials, so one option is N_eff = 10,000, giving a very strong prior (bets barely move the line). That is usually too strong because the model is misspecified and its inputs (ratings, sigma, trend) are uncertain. So use a smaller effective N, e.g. N_eff = 10,000 / k with k > 1 (e.g. k = 100 → N_eff = 100), and tune k via backtests (Brier score, calibration, or house edge) rather than α and β directly.

**2. Rating history (recommended).** Use the amount of rating history for the shooter(s) in the market: less history ⇒ more uncertainty ⇒ smaller α+β ⇒ bets move the line more.

- **Single-shooter market** (e.g. "Max 1st–3rd"): use that shooter's match count (or stage count).
- **Two-shooter market** (e.g. spread): use the **minimum** (or geometric mean) of the two shooters' history so the weaker link drives confidence.

Formula:

```
N_eff = clamp(scale × log(1 + history_count), N_min, N_max)
α = P × N_eff
β = (1 − P) × N_eff
```

Implementation parameter names: `nEffScale` (scale), `nEffMin`, `nEffMax`. The logarithmic scaling reflects diminishing marginal information from additional matches: the 5th stage tells you much more about a shooter's ability than the 50th, and the 50th tells you much more than the 200th. Under linear scaling, a 200-stage veteran would get a dramatically stiffer prior than a 50-stage regular; under log scaling, the difference is modest (`log(201) − log(51) ≈ 1.37`), which better reflects the actual reduction in uncertainty.

This also helps when a well-established shooter has an anomalous stretch (equipment change, injury). Under linear scaling, their deep history creates a near-immovable prior that sharp bettors can barely dent. Under log scaling, the prior is still informed but not a brick wall.

- **N_min** (nEffMin): floor so the prior is never useless (e.g. 20).
- **N_max** (nEffMax): cap so the prior is never rigid (e.g. 150).
- **scale** (nEffScale): controls how quickly N_eff grows with history. Tune so that "typical" veterans (30–60 matches) yield N_eff in the 50–100 range. With log scaling, scale values in the 10–25 range are reasonable (e.g. scale = 15: 30 matches → `15 × log(31) ≈ 51.5`, 60 matches → `15 × log(61) ≈ 61.6`).

The implementation uses the subject's history length in **stages** (from the rating algorithm, e.g. Elo length or Glicko2 stages) and computes N_eff in [calculator.dart](lib/data/prediction_game/bayesian_odds/calculator.dart); see also [BayesianOddsConfig](lib/data/prediction_game/bayesian_odds/config.dart).

**3. Variance from the Monte Carlo.** The Monte Carlo is a binomial with N = 10,000; its estimate P̂ has variance P(1−P)/10,000. We could set (α, β) by matching the Beta mean and variance to (P, σ²) (method of moments), then optionally scale (α, β) down so one sharp bet can still move the line by a desired amount.

**4. Calibration / empirical Bayes.** If we have historical predictions and outcomes, we can bin by predicted P, estimate empirical variance of outcomes, and fit an effective N (or α, β) so the prior variance reflects observed miscalibration. Most principled statistically but requires prediction-vs-outcome data.

**Recommendation:** Use **rating history** to set N_eff, then α = P×N_eff and β = (1−P)×N_eff. That gives one main lever (history → confidence) instead of two arbitrary numbers, and aligns with the idea that thin history should reduce confidence.

### Bayesian Update Rule

When a player places a bet, we update:

```
α_new = α_old + w × signal_for
β_new = β_old + w × signal_against
```

Where:

- **w** = weight of the bet (based on size, player skill, timing)
- **signal_for** = 1.0 if betting FOR the outcome, 0.0 otherwise
- **signal_against** = 1.0 if betting AGAINST the outcome, 0.0 otherwise

For single-sided markets (only betting "for" outcomes):

```
α_new = α_old + w
β_new = β_old
```

All markets in the prediction game are 'for': while a prediction of 15th-last is technically a bet against the subject finishing 1st-14th, it is phrased as a positive prediction rather than a negative one, so we still adjust α.

## Bet Weighting Function

Not all bets carry equal information. The weight depends on:

### 1. Bet Size Relative to Bankroll

```
raw_conviction = bet_amount / maximum_wager
```

where `maximum_wager` is the lowest of the player's balance, their tier max wager, and any time-based limits (stored per wager at placement). Raw conviction is typically 0.01 to 0.20 (1% to 20% of effective bankroll).

**Rationale**: A $100 bet from a $1000 bankroll (10%) shows higher conviction than $10 from $10,000 (0.1%).

**Log transform and optional clamping.** In practice, many players bet small amounts relative to their bankroll even when confident — e.g., 5 units on a 1000-unit bankroll yields raw conviction 0.005, which nearly zeros the weight. To avoid drowning out small bets entirely, apply a configurable transform before using conviction in the weight formula:

```
raw_conviction = bet_amount / maximum_wager
conviction = f(raw_conviction)
```

Options for `f` (all configurable, or disabled for raw linear conviction):

- **Log transform**: `log(1 + raw_conviction × k) / log(1 + k)`. Raises the floor for small bets while preserving the ordering (larger bets still count more). With `k = 5`, a 0.5% raw conviction maps to ~0.015 instead of 0.005; a 20% raw conviction maps to ~0.65 instead of 0.20. Higher `k` = more aggressive (steeper curve, small bets count relatively more). The implementation uses `convictionLogK` (default 5). **Note:** `k = 0` would yield division by zero in the formula; if linear conviction is desired, the implementation would need a special case (e.g. use raw conviction when k ≤ 0).
- **Output range [floor, 1]**: The implementation rescales the log transform into [convictionFloor, 1]: when `convictionFloor` > 0, conviction = convictionFloor + (1 − convictionFloor) × logTransform(raw). Use 0 for no floor. When `maximum_wager` is not available at placement time, raw conviction is set to `defaultConviction` and the same log transform and rescaling apply. See [BayesianOddsConfig](lib/data/prediction_game/bayesian_odds/config.dart) and [BayesianOddsWager.calculateWeight](lib/data/prediction_game/bayesian_odds/wager_data.dart).

Tune these based on production behavior. If most players bet small regardless of confidence, use an aggressive transform or floor so that bets still move the line. Configurability is important — allow toggling the transform, `k`, and `floor` without code changes.

### 2. Player Skill Multiplier (Sharpness)

The implementation calls this **sharpness**: the same concept as skill multiplier.

```
actual_accuracy   = (resolved bets won) / (resolved bets)
expected_accuracy = average of wager probabilities over resolved bets
sharpness         = actual_accuracy / expected_accuracy
```

So a player who wins more often than their odds implied is sharp (multiplier > 1); one who wins less is downweighted. The implementation uses `PredictionLeaderboardEntry.fromPlayer(..., LeaderboardSortMode.sharpness, ...).value`.

**Examples**:

- 40% win rate (weak player): multiplier = 0.8 → downweight their bets
- 50% win rate (average): multiplier = 1.0 → neutral
- 70% win rate (sharp): multiplier = 1.4 → upweight their bets

**Minimum sample size**: Require at least `minSharpnessBets` resolved bets (e.g. 5 or 10) before applying the adjustment; otherwise use 1.0. The implementation clamps sharpness to `sharpnessClampMin`..`sharpnessClampMax` (e.g. 0.5..2.0).

Naively counting successes vs. 50-50 overweights predictions from someone who wins 80% bets at an 80% rate, and underweights predictions from someone who wins 10% bets at a 20% rate—the latter should be the stronger signal.

### 3. Time Decay

```
days_until_match = (match_date - bet_date).days
time_decay = exp(-λ × days_until_match)
```

The implementation clamps time decay to a minimum of 0.5 (and maximum 1.0), so very early bets are not discounted below half weight.

Where λ controls decay rate (config: `timeDecayLambda`). Suggested values:

- **λ = 0.01**: Slow decay (30 days out = 75% weight)
- **λ = 0.02**: Moderate decay (30 days out = 54% weight); implementation default.
- **λ = 0.05**: Fast decay (30 days out = 22% weight)

**Rationale**: Bets placed closer to the match incorporate more recent information.

### 4. Combined Weight

Weight is computed by [BayesianOddsWager.calculateWeight](lib/data/prediction_game/bayesian_odds/wager_data.dart) using [BayesianOddsConfig](lib/data/prediction_game/bayesian_odds/config.dart): conviction (log transform, then rescaling to [convictionFloor, 1] when floor > 0; or defaultConviction when maxWager is null, with the same transform), sharpness clamped to [sharpnessClampMin, sharpnessClampMax], time decay exp(−λ × days) clamped to [0.5, 1.0] (λ = `timeDecayLambda` in config), and baseWeight.

**baseWeight**: Controls overall sensitivity to bets

- **baseWeight = 5**: Conservative (bets move odds slowly)
- **baseWeight = 10**: Moderate (recommended starting point)
- **baseWeight = 20**: Aggressive (bets move odds quickly)

## Step-by-Step Example (Conceptual)

The following illustrates how bet weight updates a **single wager's** posterior (α, β) and thus that wager's implied probability. In the full pipeline we do not persist per-market state: we compute posteriors for every wager (with similarity-based effective weight when evidence is clustered), find the single δ that best fits them (see "Cross-Market Adjustment via Distribution Shift"), then evaluate any requested market under the shifted distribution. This example shows the same weight math that feeds into that process, but since the combinatorics of the prediction game mean we will rarely have substantial action in the same market, the odds adjustment is a toy example of the concept rather than a final product.

### Initial State

**Market**: "Max Michel finishes 1st-3rd at 2025 Area 4 Championship"

**Model prediction**:

- P(outcome) = 0.65 (65%)
- Model tested on 100 similar predictions: α = 65, β = 35
- With 5% house edge: decimal odds = 1/(0.65/0.95) ≈ 1.46

### Bet 1: Weak Player, Small Bet, Early

**Player A places bet**:

- Amount: $10
- Bankroll: $500
- Win rate: 45% (on 20 resolved bets)
- Days until match: 30

**Calculate weight**:

```
conviction = 10/500 = 0.02
skill = 0.45/0.50 = 0.90
time_decay = exp(-0.10 × 30) = 0.0498
weight = 0.02 × 0.90 × 0.0498 × 10 = 0.009
```

**Update**:

```
α_new = 65 + 0.009 = 65.009
β_new = 35
P_new = 65.009/100.009 = 0.6501
```

**New odds**: 1/(0.6501/0.95) ≈ 1.462

**Result**: Odds barely moved (1.46 → 1.462) due to weak signal.

### Bet 2: Sharp Player, Large Bet, Late

**Player B places bet**:

- Amount: $100
- Bankroll: $500
- Win rate: 65% (on 40 resolved bets)
- Days until match: 2

**Calculate weight**:

```
conviction = 100/500 = 0.20
skill = 0.65/0.50 = 1.30
time_decay = exp(-0.10 × 2) = 0.8187
weight = 0.20 × 1.30 × 0.8187 × 10 = 2.13
```

**Update** (from previous state):

```
α_new = 65.009 + 2.13 = 67.139
β_new = 35
P_new = 67.139/102.139 = 0.6573
```

**New odds**: 1/(0.6573/0.95) ≈ 1.445

**Result**: Odds moved noticeably (1.462 → 1.445) due to strong signal.

### Summary of Movement


| State       | α      | β   | P(outcome) | Decimal Odds | Moneyline |
| ----------- | ------ | --- | ---------- | ------------ | --------- |
| Initial     | 65.000 | 35  | 0.6500     | 1.462        | -217      |
| After Bet 1 | 65.009 | 35  | 0.6501     | 1.462        | -217      |
| After Bet 2 | 67.139 | 35  | 0.6573     | 1.445        | -224      |


The sharp player's late, large bet moved the line by 7 moneyline points.

## Cross-Market Adjustment via Distribution Shift

### The Problem

Player bets on "Max Michel 1st-3rd" but there's also a market for "Max Michel 1st-5th". These are related: if money suggests Max is more likely to finish 1st-3rd, he's probably also more likely to finish 1st-5th. When generating odds for any market, we need to incorporate evidence from all compatible previous bets on the same shooter. Compatible, at present, means either place, or percentage and spread. See the appendices for thoughts on unifying place and percentage.

### Architectural Model: Compute on Demand

We do **not** maintain persistent per-market states that are mutated as bets arrive. Instead, odds for any market are computed fresh from the raw bet history when needed. Accepted bets are never retroactively repriced — each bet is locked at the odds displayed at the time it was placed. But every accepted bet becomes evidence that shifts the line for all **future** odds generation involving its subject.

The flow when generating odds for a market:

1. Start with the MC model distribution for the shooter against the current field.
2. Gather all previously accepted bets on any compatible market for the same subject. (The bettor's own prior wagers may be excluded if they point in the opposite direction — see "Bettor Wager Exclusion.")
3. Compute the cumulative implied distribution shift (δ) from those bets.
4. Evaluate P(requested market) under the shifted distribution.
5. Apply house edge → display odds.

If the bettor accepts, their bet joins the evidence pool for all future odds.

### Market Linking: Same Subject

We do **not** need a continuous similarity function to decide *whether* to consider a bet. Same subject is sufficient. This is trivial in the case of single-competitor markets. We create virtual percentage markets for spread predictions: a spread implies that competitors will finish either above or below their modeled individual percentages, based on their initial modeled separation and the size of the spread.

### The Key Insight

A bet is not just evidence about one specific outcome range — it is evidence that the **entire finish distribution is shifted** in a particular direction. A bet on "John Smith 1st-10th" at long odds when the model expects him at ~27th doesn't just say "1st-10th is more likely." It says "the true distribution is shifted toward better finishes than the model thinks."

This shift affects every market for that shooter. The question is: by how much?

A naive approach would use heuristics (overlap, proximity to model center, odds-based multipliers) to estimate the effect on each market. But these heuristics get the shape systematically wrong. The actual probability change from a distribution shift peaks near the **center of the distribution** (where the PDF is densest), not in the tails. A linear proximity factor that increases with distance from the model center over-weights tail markets and under-weights the markets that are actually most affected.

Since the Monte Carlo simulation data is available during odds generation, we can compute the exact effect by shifting the MC samples directly. This replaces direction heuristics, proximity factors, and odds multipliers with a single, principled calculation.

### Computing the Cumulative Distribution Shift (δ)

The Monte Carlo simulation produces N samples (e.g. 10,000) for each shooter. Each sample is a place and percentage finish against the field:

```
Trial 1: finished 23rd at 81%
Trial 2: finished 31st at 74%
Trial 3: finished 18th at 86%
...
Trial 10000: finished 27th at 79%
```

The model probability for any prediction is just a count: `P_model(1st-10th) = (trials finishing 1st-10th) / 10000`.

We model the cumulative bet evidence as a **location shift**: slide every sample by a constant δ.

```
shifted_finish(trial_i) = original_finish(trial_i) - δ    // for place (lower = better)
shifted_pct(trial_i)    = original_pct(trial_i) + δ       // for percentage (higher = better)

// note that δ is in units of 'places better or worse' for place predictions and 'percentage points
// better or worse' for percentage and spread predictions.
```

The implementation treats **each wager independently**. There is no aggregation by market predicate: two bets on "1st-10th" are two separate units, each with its own weight, model probability, and posterior. We find the single δ that best fits all wager posteriors simultaneously via weighted least squares, using each wager's **raw** weight in the objective (see "Similarity Between Wagers" for how effective weight is used only in the posterior). Note that when generating odds for a specific bettor, the bettor's own opposite-direction wagers may be excluded from the wager list before this step — see "Bettor Wager Exclusion."

**Per-wager quantities:**

```
For each wager W:
  weight(W)       = raw bet weight (conviction × skill × time decay × base weight)
  alpha(W)        = P_model(W) × N_eff
  posteriorWeight(W) = weight(W) + Σ (similarity-based additional weight from other wagers)
  P_posterior(W)  = (alpha(W) + posteriorWeight(W)) / (N_eff + posteriorWeight(W))

Find δ that minimizes:
  Σ  weight(W) × (P_shifted(W, δ) − P_posterior(W))²
over all wagers W
```

So: the **posterior** for each wager uses an effective weight (raw + similarity-derived) so that clustered evidence creates a larger hump in the updated distribution. The **objective** (WLS) uses only the raw weight, so the δ search is not double-counting similar wagers. The objective is smooth in δ but not unimodal (see below); we use a coarse grid to choose the right valley, then golden section to refine within it.

### Similarity Between Wagers

When several wagers target similar outcomes (e.g. "1st-10th" and "1st-5th", or "above 90%" and "above 92%"), they represent clustered evidence: multiple predictions at or near one point should make a bigger hump in the new-information distribution than the same total weight spread across unrelated markets. The implementation adds **additional weight** to each wager from nearby wagers, using a similarity measure; that additional weight is used only when computing the posterior, not in the WLS objective.

**Place wagers:** Similarity is **asymmetric**: when adding weight to wager W from wager V, use the fraction of V's range that overlaps W, so that a narrow bet (e.g. 1st-1st) fully supports a containing range (1st-3rd) but a wide bet only partly supports a narrow one. For ranges [a, b] (receiver W) and [x, y] (contributor V):

```
intersection = max(0, min(b, y) − max(a, x) + 1)
sizeFrom     = y − x + 1
similarity(W, V) = intersection / sizeFrom   (0 if sizeFrom == 0)
```

Example: Adding to 1st-3rd from 1st-1st → intersection = 1, sizeFrom = 1 → similarity = 1.0. Adding to 1st-1st from 1st-3rd → intersection = 1, sizeFrom = 3 → similarity = 1/3. "1st-10th" from "1st-5th" → 5/5 = 1.0; "1st-5th" from "1st-10th" → 5/10 = 0.5. "1st-10th" and "12th-16th" → intersection = 0 → similarity = 0.

**Percentage wagers:** Similarity uses a decay in distance following a sigmoid curve. Let `distance = |pct_a − pct_b|`. If `distance > maxDistance` (e.g. 0.05), similarity = 0. Otherwise:

```
x = distance / maxDistance
similarity = 1 / (1 + exp(steepness × (x − 0.5)))
```

Config: `percentageSimilaritySteepness` (default 20), `percentageSimilarityMaxDistance` (default 0.05). Two percentage thresholds within the max distance get a positive similarity that decays as they move apart. The implementation treats opposite-direction predictions (e.g. "above 90%" vs "below 85%") as dissimilar (similarity 0). See [calculator.dart](lib/data/prediction_game/bayesian_odds/calculator.dart) `_percentageSimilarity` and `_similarity`.

**Effective weight for posterior:** For each wager W, for every other wager V with similarity(W, V) > 0, add `similarity(W, V) × weight(V) / nearbyCount` to W's effective weight, where `nearbyCount` is the number of such V. Then:

```
posteriorWeight(W) = weight(W) + Σ_V additionalWeight(W, V)
P_posterior(W)     = (alpha(W) + posteriorWeight(W)) / (N_eff + posteriorWeight(W))
```

The objective term for W remains `weight(W) × (P_shifted(W) − P_posterior(W))²` — **raw weight only**.

**Why raw weight in the objective?** Similarity fixes a flaw in the per-wager setup. Two wagers on nearly the same outcome (e.g. "above 80%" and "above 82%") are stronger evidence than one; but if we treat them as fully independent, we get two separate posteriors each with one unit of weight — (α + w)/(N_eff + w) twice — instead of one posterior with combined weight, (α + 2w)/(N_eff + 2w). So we add similarity-derived weight when computing the posterior, which makes clustered wagers produce stronger posteriors and thus a larger δ (the optimizer must move δ further to match them). We do **not** use that boosted weight in the objective: each wager should influence the δ fit in proportion to the evidence it actually represents (its raw weight). Using posteriorWeight in the objective would give similar wagers extra pull and overweight clustered evidence relative to lone wagers elsewhere.

**Grid search then golden section (multimodal objective).** The WLS objective can have **multiple local minima**. When wagers point in opposite directions (e.g. one on 1st-1st, one on 2nd-10th), one term pulls for positive δ and the other for negative δ. A **wide** place range (e.g. 2nd-10th) has a steeper P_shifted(δ) than a single-place range (1st-1st), because mass moves in or out of a wide band quickly as δ changes. So the wide-range term's contribution to the objective can drop sharply in one valley (e.g. at strongly negative δ) even though the narrow-range term is badly fitted there. Golden section search assumes **unimodality** and only shrinks the bracket; started over the full range, it can converge into that "wrong" valley (e.g. δ ≈ −9) and never see the better compromise (e.g. δ ≈ 0). To avoid that, we first evaluate the full objective on a **coarse grid** over [searchLo, searchHi] (e.g. step 2 places for place, 0.05 for percentage), take the grid point with the smallest objective as the chosen valley, then run **golden section** only within the bracket [bestGridDelta − gridStep, bestGridDelta + gridStep]. That way we pick the correct valley from the grid and refine inside it. The implementation logs the best grid point and any grid local minima/maxima for diagnostics.

The δ search is implemented in [calculator.dart](lib/data/prediction_game/bayesian_odds/calculator.dart): `_totalObjective` for the full WLS sum at a given δ; a coarse grid over the search range to find the best grid delta; then `_calculateDelta` (golden section) over the bracket around that delta; objective sums raw weight × squared error per wager.

**Example:** Three wagers on John Smith — one on 1st-10th (weight 2.13), one on 12th-16th (weight 0.8), one on 1st-5th (weight 0.3). The 1st-10th and 1st-5th wagers have overlapping place ranges, so each gets additional effective weight from the other (asymmetric: 1st-5th gives full weight to 1st-10th; 1st-10th gives half weight to 1st-5th); their posteriors are slightly stronger. The δ search minimizes raw-weight WLS across all three.

**When posteriors conflict** (e.g. a wager on 1st-10th and a wager on 35th-40th pointing in opposite directions), the weighted least squares naturally compromises, with heavier wagers dominating.

**Continuous place evaluation (smooth boundaries):** Place evaluation uses **fractional contributions** so that P_shifted is continuous in δ. A bang-bang rule (e.g. count a trial as in-range iff shifted place ≤ threshold + 0.5) would make P_shifted jump at half-integer δ and produce an easily exploitable objective for the optimizer. Instead, each trial contributes a value in [0, 1] to the range count:

- **Shifted place:** `s = place - δ`, with s clamped to a minimum of 0.5 so the "1st" band is [0.5, 1.5].
- **Place bands:** Place k occupies the continuous band [k−0.5, k+0.5]. For a range [L, R], full contribution (1.0) when s ∈ [L−0.5, R+0.5]. When L ≥ 2, a linear ramp over [L−1, L−0.5] at the lower edge (so as δ increases and a trial at place L crosses into the range, contribution increases smoothly from 0 to 1). A linear ramp over [R+0.5, R+1] at the upper edge (as δ moves a trial at place R+1 out of range, contribution falls smoothly from 1 to 0).

So P_shifted changes continuously with δ; small shifts do not dump all mass across a place boundary. Implementation: [place_evaluation.dart](lib/data/ranking/prediction/odds/place_evaluation.dart) (`placeShifted`, `placeRangeContribution`); used by [BayesianOddsWager.evaluatePlaceAgainstSimulation](lib/data/prediction_game/bayesian_odds/wager_data.dart) and by the place-probability path in [probability.dart](lib/data/ranking/prediction/odds/probability.dart) when a place δ is applied.

### Generating Odds Under the Shifted Distribution

Once δ is computed, generating odds for any market is straightforward: count how many shifted samples satisfy the market's predicate, then apply the logit clamp if implemented. See the wager/odds pipeline (e.g. [wager_updater.dart](lib/data/prediction_game/bayesian_odds/wager_updater.dart) and related callers) for how δ is applied and probabilities are produced. Note that the logit clamp is not yet implemented (and may not be necessary, going by early testing).

This is the same computation whether the requested market has prior bets on it or not. A bet on 1st-10th naturally moves the odds for 12th-16th, for 1st-10th itself (line movement), and for 35th-40th — all from the same δ, all with the correct magnitude.

### Worked Example: Place Markets (End-to-End)

**Setup:** John Smith, model expects ~27.5th finish. N = 10,000 MC trials. N_eff = 100.

**Prior wagers (each independent):**

- Wager A: "John Smith 1st-10th", sharp player, late, raw weight = 2.13
- Wager B: "John Smith 1st-5th", moderate player, raw weight = 0.50

**Step 1 — Similarity and posteriors:**

Place similarity (to, from) = |to ∩ from| / |from|. So A (1st-10th) gets similarity(A,B) = 5/5 = 1.0 from B; B (1st-5th) gets similarity(B,A) = 5/10 = 0.5 from A. With one nearby wager each: A gets 1.0 × 0.50 / 1 = 0.50 from B; B gets 0.5 × 2.13 / 1 = 1.065 from A. Thus:

- Wager A: posteriorWeight = 2.13 + 0.50 = 2.63; P_model = 0.012 → P_posterior = (0.012 × 100 + 2.63) / (100 + 2.63) ≈ 0.037
- Wager B: posteriorWeight = 0.50 + 1.065 = 1.565; P_model = 0.003 → P_posterior = (0.003 × 100 + 1.565) / (100 + 1.565) ≈ 0.0184

Both posteriors point toward better finishes. The objective uses **raw** weights (2.13 and 0.50) for the WLS terms.

**Step 2 — Find δ:** Golden section search minimizes 2.13×(P_shifted_A − 0.0334)² + 0.50×(P_shifted_B − 0.0184)². Finds δ ≈ 1.8 positions (model expected ~27.5th, implied ~25.7th).

**Step 3 — Generate odds for any requested market under the shifted distribution:**


| Requested Market | P_model | P_shifted | Change                      |
| ---------------- | ------- | --------- | --------------------------- |
| 1st-5th          | 0.003   | 0.008     | +0.005 (line moved)         |
| 1st-10th         | 0.012   | 0.033     | +0.021 (line moved)         |
| 12th-16th        | 0.045   | 0.058     | **+0.013**                  |
| 20th-25th        | 0.220   | 0.240     | **+0.020** (largest change) |
| 25th-30th        | 0.280   | 0.272     | **-0.008**                  |
| 35th-40th        | 0.110   | 0.098     | **-0.012**                  |


Key observations:

- **Line movement works naturally.** A new bettor asking for odds on 1st-10th or 1st-5th sees updated probabilities. Prior bets were the evidence that moved the line.
- **Direction is automatic.** Markets on the "better" side of the model center get positive shifts; markets on the "worse" side get negative. No direction heuristic needed.
- **Strength has the right shape.** The largest positive change is at 20th-25th — just on the "better" side of the model mode, where the PDF is densest. The bet targets (1st-10th, 1st-5th), despite having the direct evidence, have smaller absolute changes because the tail is thin (although the probabilites change more in relative terms).
- **Disjoint-but-same-side works correctly.** 12th-16th has no overlap with either bet range, but still gets a positive shift because the distribution shift moves mass into that range.
- **Works for any distribution shape.** Skewed, multimodal, heavy-tailed — the MC samples represent the actual distribution. The only caveat is that bets cannot add uncertainty or width; those come from the model and are not affected by the shift.

### Worked Example: Percentage Markets

**Setup:** Jane Doe, model expects ~75th percentile. N = 10,000 MC trials. N_eff = 100.

**Prior wagers (each independent):**

- Wager A: "above 95%", sharp player, raw weight = 1.5
- Wager B: "above 90%", moderate player, raw weight = 0.4

**Step 1 — Similarity and posteriors:**

Percentage thresholds 95% and 90% are 5% apart; with maxDistance = 0.05 they are at the boundary, so similarity may be small (e.g. exponential decay gives a modest value). If we ignore similarity for this example: posteriorWeight = raw weight for each. Then:

- Wager A: P_model = 0.018 → P_posterior = (0.018 × 100 + 1.5) / (100 + 1.5) = 0.033
- Wager B: P_model = 0.052 → P_posterior = (0.052 × 100 + 0.4) / (100 + 0.4) = 0.056

Both point upward — consistent. The objective uses raw weights (1.5 and 0.4).

**Step 2 — Find δ:** Golden section search minimizes the raw-weight WLS over the two wagers. Finds δ ≈ 1.2 percentage points upward (model expected ~75%, implied ~76.2%).

**Step 3 — Generate odds for any requested market:**


| Requested Market | P_model | P_shifted | Change                |
| ---------------- | ------- | --------- | --------------------- |
| Above 95%        | 0.018   | 0.033     | +0.015 (line moved)   |
| Above 90%        | 0.052   | 0.072     | **+0.020**            |
| Above 85%        | 0.125   | 0.155     | **+0.030**            |
| Above 80%        | 0.290   | 0.325     | **+0.035** (largest!) |
| Below 70%        | 0.195   | 0.172     | **-0.023**            |
| Below 60%        | 0.085   | 0.070     | **-0.015**            |


**Above 80%** sees the largest change because it's near the model's mode where the PDF is densest. Below 60% gets a stronger penalty than below 70%, because it's further from the model center on the "wrong" side.

### Why This Replaces Proximity Heuristics

A linear proximity factor (increasing with distance from the model center toward the bet) gets the strength allocation systematically wrong:


| Target                 | True Change (from distribution shift) | Linear Proximity (old) |
| ---------------------- | ------------------------------------- | ---------------------- |
| >80% (near model mode) | **+0.035** (largest)                  | 0.25 (weak)            |
| >85%                   | +0.030                                | 0.50 (moderate)        |
| >90%                   | +0.020                                | 0.75 (strong)          |
| >95% (bet target)      | +0.015                                | 1.00 (strongest)       |


The linear heuristic gives the most weight to the market that changes the *least*, and the least weight to the market that changes the *most*.

The distribution shift replaces four separate heuristics (direction, proximity, odds multiplier, per-type helpers) with a single principled calculation that:

- Gets direction right automatically (sign of change)
- Gets strength right automatically (peaks where the PDF is densest)
- Handles all prediction types uniformly (place, percentage, spread — just different predicates on the MC samples)
- Handles non-normal distributions natively (the MC samples represent the actual distribution)
- Absorbs the odds multiplier (a long-odds bet produces a bigger posterior shift, which produces a larger δ, which produces larger changes across all markets)

The only remaining heuristic is the bet weight (conviction × skill × time decay × base weight), which is appropriate — it represents the *quality of the evidence*, while the distribution shift represents *what the evidence implies*.

## Risk Management

### Maximum Odds Movement

Protect against over-adjustment. After computing P_shifted from the shifted MC distribution, clamp the movement.

A naive linear clamp (`maxMove = modelP × fraction`) breaks at extreme probabilities: for a long-shot market with P = 0.01, a 20% cap allows only ±0.002 of movement — the line is effectively frozen. But long-shot bets carry high informational content (the bettor is risking a lot relative to expected return), so they should have *more* room to move, not less.

The fix is to clamp symmetrically in **log-odds space**. The logit transform `logit(p) = ln(p / (1 − p))` maps probabilities to the real line, where a fixed-width band has uniform meaning across the probability range: a shift of 1 logit unit roughly doubles or halves the odds ratio, regardless of baseline probability. The config parameters `maxLogitShift`, `clampEvidenceTau`, and `clampMaxMultiplier` govern this; see [BayesianOddsConfig](lib/data/prediction_game/bayesian_odds/config.dart). A value of 1.0 for `maxLogitShift` means the odds ratio can roughly double or halve. Optionally, when `clampEvidenceTau > 0` and total bet weight is available, the effective clamp widens with evidence (see "Evidence-Dependent Clamp Width"). The allowed range in probability space (for `maxLogitShift = 1.0`):


| modelP | Allowed range  | Absolute width |
| ------ | -------------- | -------------- |
| 0.01   | [0.004, 0.027] | 0.023          |
| 0.05   | [0.019, 0.125] | 0.106          |
| 0.50   | [0.269, 0.731] | 0.462          |
| 0.95   | [0.875, 0.981] | 0.106          |
| 0.99   | [0.973, 0.996] | 0.023          |


Key properties:

- **Symmetric**: P = 0.05 and P = 0.95 get the same absolute width (0.106).
- **Long shots can move**: P = 0.01 gets a range of [0.004, 0.027], not the frozen [0.008, 0.012] of a linear 20% clamp.
- **Favorites can't exceed 1.0**: The sigmoid naturally stays in (0, 1).
- **Primary tunable**: `maxLogitShift` has uniform meaning across the probability range — "how many doublings/halvings of the odds ratio are allowed?" Optional evidence-dependent scaling adds `clampEvidenceTau` and `clampMaxMultiplier` (see "Evidence-Dependent Clamp Width").

Compare to the linear clamp (`maxMove = modelP × 0.20`):


| modelP | Log-odds range | Linear 20% range |
| ------ | -------------- | ---------------- |
| 0.01   | [0.004, 0.027] | [0.008, 0.012]   |
| 0.05   | [0.019, 0.125] | [0.040, 0.060]   |
| 0.50   | [0.269, 0.731] | [0.400, 0.600]   |
| 0.95   | [0.875, 0.981] | [0.760, 1.000]   |


The linear clamp over-restricts long shots and over-permits near-certainties.

**Implementation:** The clamp is applied in [wager_updater.dart](lib/data/prediction_game/bayesian_odds/wager_updater.dart) after δ is computed. The current (pre-clamp) raw probability is converted to logit; allowed probability bounds are `logit⁻¹(logit(p) ± maxLogitShift)` using the effective max logit shift (evidence-dependent when `clampEvidenceTau > 0`). From those bounds, best and worst allowed decimal odds are derived via [PredictionProbability.fromRawProbability](lib/data/ranking/prediction/odds/probability.dart); the final odds passed to `recalculateProbabilityWithDelta` are the intersection of that logit-derived band with any caller-supplied `bestPossibleOdds`/`worstPossibleOdds`. Total bet weight used for evidence-dependent clamp width is the sum of weights from the subject's contributing wagers (for spreads, the geometric mean of subject and underdog weight sums).

### Evidence-Dependent Clamp Width

Should the clamp widen when multiple wagers pull the odds in the same direction? The δ search already weights wagers by raw bet weight, so more consensus yields a larger δ and thus larger P_shifted. The fixed clamp then applies a uniform ceiling regardless of evidence strength.

**Arguments for widening with evidence:** One bet can be noise; many agreeing bets are stronger evidence. A fixed band can be overly conservative when sharp consensus suggests the model is wrong. Widening the clamp for higher total weight lets the Bayesian machinery move further when evidence is strong.

**Arguments for keeping it fixed:** The clamp may be a deliberate ceiling on model deviation — "we never move more than X from fundamentals." Widening with evidence could amplify herding (early bets move the line → new bettors pile on → line moves further). A single tunable is simpler.

**Recommendation:** Keep the fixed clamp as default. If backtests show the clamp frequently cuts off shifts that posteriors deem well-supported, enable evidence-dependent scaling. Tune via Brier score and calibration.

When evidence-dependent scaling is enabled (`clampEvidenceTau > 0`), the effective max logit shift grows with total weight on the shooter using an exponential approach to the maximum:

```
multiplier = 1 + (clampMaxMultiplier − 1) × (1 − exp(−totalWeight / clampEvidenceTau))
effectiveMaxLogitShift = multiplier × maxLogitShift
```

The single tunable **`clampEvidenceTau`** (tau) is the total bet weight at which the multiplier reaches ~63% of the way from 1.0 to `clampMaxMultiplier`. This gives it a direct interpretation: "how much evidence before the clamp is substantially widened?" The exponential form naturally saturates at `clampMaxMultiplier` without a hard cap, and the useful range of tau is wide (2–50+), unlike the narrow sweet spot of a log-based scaling factor.

Example with `clampMaxMultiplier = 2.0`:

| totalWeight | tau=5 → mult | tau=10 → mult | tau=20 → mult |
| ----------- | ------------ | ------------- | ------------- |
| 2           | 1.33         | 1.18          | 1.10          |
| 5           | 1.63         | 1.39          | 1.22          |
| 10          | 1.86         | 1.63          | 1.39          |
| 20          | 1.98         | 1.86          | 1.63          |
| 50          | ~2.0         | 1.99          | 1.92          |

With `maxLogitShift = 1.0` and `tau = 10`, a single sharp bet (weight ~2) produces only modest clamp widening (1.18×), five sharp bets (total ~10) push to 1.63×, and the asymptote of 2.0× is effectively reached around 50 total weight.

### Exposure Limits

In a real-money context, the house would need to track total exposure (sum of potential payouts minus wager amounts across all open wagers) and throttle odds movement when exposure grows large relative to the house's bankroll. This would work by computing an exposure multiplier that scales down bet weights as exposure increases, making it harder for new bets to move the line when the house is already heavily exposed. The multiplier would apply to `baseWeight` in the bet weighting function.

In our play-money prediction game, this is unnecessary — the house has an effectively unlimited bank, and there is no real financial risk to manage. If a real-money mode were ever added, exposure limits would become important to prevent the house from taking on unbounded liability.

### Decay Over Time

The bet weighting function already includes time decay (bets placed further from the match get lower weight). In the compute-on-demand model, this decay is applied naturally when bet weights are computed during odds generation — old bets always contribute less to δ by dint of their timing relative to the match start date.

## Implementation Considerations

### Data Storage

No persistent per-market Bayesian state is needed. The inputs to odds generation are:

1. **MC samples per shooter** (pre-sorted by finish position and by percentage), generated at simulation time.
2. **Accepted bet history** — each bet stores its market (prediction), bet weight, and acceptance timestamp.
3. **N_eff per shooter** — derived from rating history (see "Principled Setting of α and β").

Odds are computed from scratch on demand; δ can be cached per shooter (see "Caching δ Per Shooter" below).

### Bet Removal/Voiding

Since odds are computed from the raw bet history, voiding a bet is trivial: mark it as voided so it's excluded from future odds generation. No state to reverse, no floating-point drift. The next odds request for that shooter will naturally reflect the reduced evidence.

### Performance Optimization

The compute-on-demand model recomputes δ each time odds are requested, but the cost is modest:

1. **MC sample ordering must be preserved** — trial indices must stay aligned across shooters so that spread predictions can compare shooter A's trial *i* against shooter B's trial *i*. Sorting per-shooter samples by finish position or percentage would destroy this pairing. The samples are simply scanned in trial order.
2. **δ search** runs a coarse grid over the range (O(range/gridStep) full-objective evaluations), then golden section in the bracket around the best grid point (~15 iterations). Each evaluation is O(W × N). For place (range ~40, step 2) that's ~20 grid points plus refinement; cost remains modest for small W.
3. **Evaluating P_shifted** for the requested market is one pass over the shifted samples: O(N).
4. **Sorted copies for binary search** — maintaining a sorted copy of each shooter's samples (separate from the trial-ordered originals) would allow O(log N) boundary lookups instead of O(N) linear scans for place and percentage markets, with the break-even at roughly log₂(N) queries (~14 for N = 12,500). Spread markets would still require linear scans on the paired data. At current sample sizes the linear scan completes in microseconds, so this is not worth implementing unless profiling shows the δ search is a bottleneck.
5. **Cache δ per shooter**: See "Caching δ Per Shooter" below.
6. **Index bets by subject**: Group accepted bets by shooter for fast lookup during odds generation.

### Caching δ Per Shooter

δ for a given shooter is a function of (all prior bets on that shooter, MC samples, N_eff) — none of which depend on the market being requested. This means δ can be computed once and reused for all market evaluations on that shooter until new evidence arrives.

Since δ entries are small (a double, a timestamp, and a few links) and rarely looked up, they belong in the database rather than an in-memory cache. This gives persistence across restarts, lets us link entries to the wagers and shooter ratings that produced them, and naturally accumulates a history for line-movement visualization.

**Schema:** See [BayesianDelta](lib/data/database/schema/prediction_game/bayesian_delta.dart) (and extensions in [bayesian_delta.dart](lib/data/database/extensions/bayesian_delta.dart)). δ is stored per shooter/prediction-set with `delta`, `type` (place or percentage), and links to contributing wagers; spread is decomposed into percentage.

**Cache lookup:** When generating odds, the pipeline consults the cache first via [getBayesianDelta](lib/data/database/extensions/bayesian_delta.dart) (member number, prediction set, type, last-bet timestamp, config hash). On a cache hit, the stored δ is returned and used for all market evaluations on that shooter; δ is not recomputed. On a miss, δ is computed (e.g. in [wager_updater.dart](lib/data/prediction_game/bayesian_odds/wager_updater.dart)), saved, and then used. This reduces repeated odds requests to O(N) per market (evaluate predicate over shifted samples) rather than recomputing δ each time.

**Invalidation:** No explicit invalidation is needed — the timestamp comparison handles staleness. Old entries stay in the DB as history. When the MC simulation is re-run (new registration set), either write a new δ entry (the next odds request will recompute against the new samples) or mark a simulation boundary for the line-movement chart.

**Line-movement visualization:**

Since every δ computation writes a new entry (rather than overwriting), the DB naturally accumulates a history of how δ evolved as bets arrived. To render a line-movement chart for a specific market:

1. Query all `BayesianDelta` entries for the shooter (and prediction set/type), ordered by recency.
2. For each entry, evaluate the market's predicate against the current MC samples shifted by that entry's δ.
3. Plot the resulting probability series over time.

Each entry's `contributingWagers` link lets the chart annotate which bet(s) caused each line movement. (Specifically, each BayesianDelta object ordered by recency will have one more wager ID than the preceding one; that wager is the one that caused the line movement between delta _n_ and _n_ - 1.) The `shooterRating` link provides context for tooltips (shooter name, rating at the time).

**Note on MC simulation changes:** If the simulation is re-run (new registration set), historical δ values were computed against different samples. The δ *direction* is still meaningful (see "Reusing MC Samples Across Prediction Sets"), but evaluating old δ values against new samples may produce slightly different probabilities. For the line-movement chart, this is acceptable — mark simulation boundaries with a visual indicator and note that pre-boundary values are approximate.

### Reusing MC Samples Across Prediction Sets

As registrations change, the MC simulation may be re-run with a different field, producing a new set of samples. Wagers placed against an older prediction set were priced using the old samples. When computing δ for odds generation, it is acceptable to use the **most recent** MC samples even though some wagers targeted a slightly different field, provided the registration changes are modest (a few adds/drops in a typical field of 50–200 shooters).

**Why this works:**

- **Percentage markets** are the most robust, because a shooter's percentage finish is mostly determined by their own stage performance, not by who else is shooting. A few registration changes barely affect the percentage distribution.
- **Place markets** are slightly more sensitive, since adding a strong competitor pushes expected finishes down by roughly one position. But for small field changes this is a sub-position effect — well within the MC simulation's own sampling noise.
- **Spread markets** depend on two specific shooters' relative performance, which is mostly independent of the rest of the field.

The δ optimization finds a *relative* shift ("bets say this shooter is about 2 positions better than the model thinks"). That relative signal transfers well to a nearly-identical field even if the absolute sample values differ slightly.

**When it breaks down:** If a registration change adds or removes a *direct competitor* at a similar skill level — someone expected in the same 5-position band as the subject — that could shift the subject's distribution by several positions, making the stale samples a poor proxy. Even then, the δ will be directionally correct but may be slightly miscalibrated in magnitude.

**Why using the current samples is the principled choice:** Even if rerunning MC simulations for older prediction sets were computationally free, it would introduce a baseline mismatch. A posterior computed from the old P_model reflects "the old model's estimate, plus bet evidence." If the current model has since moved in the same direction the bet was pointing (e.g., the old model said P = 0.012 for 1st-10th, the current model says P = 0.015), then applying a δ derived from the old posterior to the current samples would overshoot — it would correct for a gap the model has already partially closed on its own. Using the current MC samples as both the prior for posteriors and the distribution being shifted keeps the two in the same "world." The bet's signal ("this shooter is better than the model thinks") is automatically attenuated if the model has moved toward the bettor's view, and amplified if it has moved away.

**Recommendation:** Always use the most recent MC samples for δ computation. Invalidate only when a new simulation is actually run (i.e., when registrations change enough to trigger a re-simulation). The error from slightly stale samples is much smaller than the inherent model uncertainty.

## Tunable Parameters Summary

All parameters live in [BayesianOddsConfig](lib/data/prediction_game/bayesian_odds/config.dart). Current implementation defaults may differ from the "Recommended" tuning column below.

| Parameter                    | Recommended | Conservative | Aggressive | Description                                                                                                                                |
| ---------------------------- | ----------- | ------------ | ---------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| **Model Confidence** (α + β) | 50-100      | 100-200      | 25-50      | Set via N_eff from rating history (see "Principled Setting of α and β"); higher N_eff = less movement from bets. Do not tune α+β directly. |
| **N_eff Scale** (nEffScale)  | 10          | 15           | 8          | Multiplier on log(1 + history) when computing N_eff. Formula: clamp(nEffScale × log(1 + history), nEffMin, nEffMax).                      |
| **N_eff Min** (nEffMin)      | 20          | 30           | 15         | Floor for N_eff.                                                                                                                           |
| **N_eff Max** (nEffMax)      | 150         | 200          | 100        | Cap for N_eff.                                                                                                                             |
| **Base Weight**              | 10.0        | 5.0          | 20.0       | Overall bet impact scaling.                                                                                                                |
| **Conviction Log K**         | 5           | 0*           | 10         | Log transform for conviction. *0 = linear but requires special-case in code (formula divides by zero).                                      |
| **Conviction Floor**         | 0.05        | 0            | 0.25       | Output range floor: conviction is rescaled to [convictionFloor, 1]. Use 0 for no floor.                                                      |
| **Default Conviction**       | 0.5         | 0.33         | 0.75       | When maximum_wager is not available, raw conviction is set to this; same log transform and rescaling apply.                                  |
| **Time Decay λ** (timeDecayLambda) | 0.02 | 0.01         | 0.05       | Rate of early bet discounting. Implementation clamps result to [0.5, 1.0].                                                               |
| **Max Logit Shift**          | 1.0         | 0.5          | 1.5        | Maximum movement in log-odds space (1.0 ≈ odds can double/halve). See "Maximum Odds Movement."                                             |
| **Clamp Evidence Tau** (clampEvidenceTau) | 10.0 | 0 (disabled) | 5.0 | Characteristic weight for evidence-dependent clamp. Total bet weight at which multiplier is ~63% of way to max. 0 = fixed clamp. See "Evidence-Dependent Clamp Width." |
| **Clamp Max Multiplier**     | 2.0         | 1.5          | 2.5        | Asymptote for evidence-dependent multiplier on maxLogitShift. See "Evidence-Dependent Clamp Width."                                        |
| **Min Sharpness Bets** (minSharpnessBets) | 5 | 10           | 5          | Minimum resolved bets (int) before applying sharpness multiplier; otherwise 1.0.                                                            |
| **Sharpness Clamp Min**      | 0.5         | 0.5          | 0.5        | Minimum allowed sharpness multiplier.                                                                                                      |
| **Sharpness Clamp Max**      | 2.0         | 1.5          | 2.5        | Maximum allowed sharpness multiplier.                                                                                                      |
| **Percentage similarity**    | —           | —            | —          | percentageSimilaritySteepness (default 20), percentageSimilarityMaxDistance (default 0.05). Place similarity is asymmetric overlap (no tunables).    |


## Testing Strategy

### Unit Tests

1. **Weight calculation**: All factors (conviction, skill, time) combine properly; time decay clamped to [0.5, 1.0]; default conviction when maxWager null.
2. **Single-wager δ**: Binary search converges to correct δ for known MC distributions. Verify with a simple uniform or Gaussian sample set where the answer is analytically known.
3. **Multi-wager δ**: Golden section search finds the δ that best fits multiple wager posteriors simultaneously (raw weight in objective). Verify with consistent and conflicting posteriors.
4. **Similarity**: Asymmetric overlap for place (|to ∩ from| / |from|) and exponential decay for percentage; posterior uses posteriorWeight, objective uses raw weight.
5. **Cross-market direction**: Same-subject wagers get correct sign (positive for same-side, negative for opposite-side). Verify that disjoint-but-same-side ranges get positive changes (e.g. wager on 1st-10th increases P for 12th-16th when model expects ~27th).
6. **Cross-market shape**: Probability changes peak near the model mode, not in the tail. For a symmetric distribution, the largest change should be near the model center, not near the bet target.
7. **Line movement**: A wager on a market shifts that same market's odds for the next request.
8. **Bounds checking**: Probabilities stay in [0, 1], max movement enforced
9. **Voiding**: Voiding a bet and regenerating odds returns to model probabilities

### Integration Tests

1. **Multiple wagers, same predicate**: Each wager is independent; similarity may add effective weight for posteriors; δ fits all wagers.
2. **Multiple wagers, different markets**: δ optimization reconciles multiple posteriors. Verify direction consistency.
3. **Probability conservation**: After applying δ, verify that the total probability mass across mutually exclusive markets remains close to the original sum (location shift preserves total mass).
4. **Place, percentage, and spread**: Verify the distribution shift works for all three prediction types with realistic MC sample distributions.
5. **Player learning**: As player's accuracy changes, future bets weighted differently
6. **Time progression**: Old bets have less predictive strength

### Validation Strategy

1. **Backtest**: Apply to historical prediction game data
2. **Compare to actuals**: Did adjusted odds better predict outcomes than model odds?
3. **Sharp player tracking**: Did sharp players' bets successfully predict outcomes?
4. **House edge**: Did adjustments maintain or improve house profitability?

## Future Enhancements

### 1. Implied Probability Arbitrage Detection

If cross-market updates create inconsistent implied probabilities, flag for review.

Example: If "Max 1st-3rd" has P=0.40 and "Max 4th-6th" has P=0.50, but those are the only possible outcomes, sum should be closer to 1.0.

### 2. Market Maker vs Player Mode

- **Opening odds**: Use pure model probabilities
- **After first bet**: Switch to Bayesian adjustment
- **Closing odds**: Consider locking odds or using pure flow-based pricing

### 3. Correlated Market Detection

Some markets are perfectly correlated:

- "Max finishes ≥95%" implies "Max finishes 1st-3rd"
- Detect and enforce consistency

### 4. Sharp Group Detection

If multiple players consistently bet together and win, treat as a single sharp entity with higher weight.

### 5. Order Book Dynamics

Instead of single odds, offer a range:

- Bid (best odds for house): Model - movement
- Ask (best odds for player): Model + movement
- Spread narrows as more bets placed (confidence increases)

## References and Further Reading

- **Bayesian Statistics**: Gelman et al., "Bayesian Data Analysis" (2013)
- **Market Making**: Harris, "Trading and Exchanges" (2003)
- **Sports Betting Mathematics**: Cortis, "Expected Values and Variances in Bookmaker Payouts" (2015)
- **Beta-Binomial Models**: Griffiths & Tenenbaum, "From mere coincidences to meaningful discoveries" (2007)

## Appendix: Implementation Reference

δ is stored in the database per "Caching δ Per Shooter" (see [BayesianDelta](lib/data/database/schema/prediction_game/bayesian_delta.dart)). The core logic lives in:

- **[calculator.dart](lib/data/prediction_game/bayesian_odds/calculator.dart)** — `calculateBayesianOddsUpdate` (per-wager weights, similarity, posteriors, grid-then–golden-section δ search); `_totalObjective`, grid over search range, `_calculateDelta` (golden section in bracket), `_similarity`, `_placeSimilarity`, `_percentageSimilarity`.
- **[wager_data.dart](lib/data/prediction_game/bayesian_odds/wager_data.dart)** — `BayesianOddsWager.calculateWeight(config)` (conviction log transform and rescaling to [convictionFloor, 1], sharpness clamp, time decay clamp); `fromDbWager` (DbWager → BayesianOddsWager, including spread decomposition and sharpness from leaderboard); `evaluatePlaceAgainstSimulation` (place evaluation using continuous boundaries from place_evaluation).
- **[place_evaluation.dart](lib/data/ranking/prediction/odds/place_evaluation.dart)** — `placeShifted(place, delta)`, `placeRangeContribution(s, bestPlace, worstPlace)` for continuous place evaluation (fractional contribution at boundaries so P_shifted is smooth in δ).
- **[config.dart](lib/data/prediction_game/bayesian_odds/config.dart)** — [BayesianOddsConfig](lib/data/prediction_game/bayesian_odds/config.dart) holds all tunables (nEff, baseWeight, timeDecayLambda, convictionLogK, convictionFloor, defaultConviction, sharpness, similarity, etc.).
- **[wager_updater.dart](lib/data/prediction_game/bayesian_odds/wager_updater.dart)** — `_calculateDeltaForSubject` orchestrates delta computation for a single subject: cache lookup, bettor wager exclusion (see "Bettor Wager Exclusion"), prior wager hydration, and isolate dispatch; returns delta and bet weights for evidence-dependent clamp. `_wagersAreSimilar` implements direction-based comparison between the incoming bet and a prior wager to decide whether to exclude it (derives direction from `abovePercentage` for percentage, `favoriteCovers` + subject role for spread, range midpoint vs. model expectation for place). After deltas are computed, the logit movement cap is applied: effective `maxLogitShift` (with optional evidence-dependent multiplier from total bet weight), then `logit⁻¹(logit(p) ± maxLogitShift)` for allowed probability bounds and thus best/worst decimal odds passed to `recalculateProbabilityWithDelta`.
- **[probability.dart](lib/data/ranking/prediction/odds/probability.dart)** — `PredictionProbability.fromRawProbability` builds a probability from a raw P for use in the logit clamp; `rawMoneylineOdds` for logging. Final decimal odds are clamped between `worstPossibleOdds` and `bestPossibleOdds` in `decimalOdds` getter.

### Delta Computation: Per-Wager + Similarity

The δ pipeline does **not** group by market. It works over a list of `BayesianOddsWager`:

1. **Similarity:** For each wager W, compute `additionalWeight[W][V] = similarity(W,V) × weight(V) / nearbyCount` for each other wager V with positive similarity (asymmetric place overlap for place, exponential decay for percentage). Then `posteriorWeight(W) = weight(W) + Σ additionalWeight[W]`.
2. **Posteriors:** For each wager W: `alpha(W) = P_model(W) × N_eff`, `P_posterior(W) = (alpha(W) + posteriorWeight(W)) / (N_eff + posteriorWeight(W))`.
3. **Objective:** Minimize `Σ weight(W) × (P_shifted(W, δ) − P_posterior(W))²` over δ. Coarse grid to select valley, then golden section in that bracket (objective can be multimodal). Use **raw** `weight(W)` in the sum, not `posteriorWeight(W)`.

See "Computing the Cumulative Distribution Shift (δ)" and "Similarity Between Wagers" above for formulas. The entry point is `calculateBayesianOddsUpdate(config, subjectHistoryLength, wagers, subjectMonteCarlo)` which returns `BayesianOddsResult(delta, log)`.

### Generating Odds After δ

Once δ is computed (or read from the BayesianDelta cache), generating odds for a requested market is one pass over the MC samples: count how many satisfy the market predicate under the shifted distribution, then apply the logit clamp (see "Maximum Odds Movement" and implementation in [wager_updater.dart](lib/data/prediction_game/bayesian_odds/wager_updater.dart)). Total weight on the shooter is summed over all wagers for evidence-dependent clamp width. No per-market state is stored; the same δ is used for every market on that shooter.

---

## Appendix: Spread Bets as Percentage Signals

### The Idea

A spread prediction like "A beats B by ≥5%" is fundamentally a claim about the *difference* between two shooters' percentage finishes. Rather than maintaining a separate δ type for spreads (which requires a two-shooter key, a separate optimization pass, and its own cache entries), we decompose each spread bet into two weak **percentage signals** — one for each shooter — and let them flow into the existing per-shooter percentage δ framework.

This eliminates the need for a separate spread delta type. Every δ is single-shooter, and spread odds are derived from the combination of two individual percentage deltas.

### Decomposition via Virtual Percentage Markets

A spread bet "A beats B by ≥X%" with weight `w` implies:

- A's percentage is higher than the model thinks (positive signal)
- B's percentage is lower than the model thinks (negative signal)

To express this as evidence the percentage δ optimizer can consume, we create **virtual percentage markets** for each shooter. The virtual market threshold is derived from the spread's implied individual requirements, not from the median, so that long-odds spread bets produce stronger signals than short-odds ones.

**Computing the virtual thresholds:**

The model's expected spread is `mean_A - mean_B` (or, given the current implementation, equivalently `median_A - median_B`—estimated performances are normal around the expected strength). The bet claims the spread should be at least X%. The "excess" beyond the model's expectation is split equally between the two shooters:

```
mean_A = mean of sortedPctSamplesA
mean_B = mean of sortedPctSamplesB
model_spread = mean_A - mean_B

// For "favorite covers" (A-B ≥ X%):
excess = spread_threshold - model_spread
threshold_A = mean_A + excess / 2
threshold_B = mean_B - excess / 2

Virtual bet for A: "A above threshold_A", weight = w × splitFactor
Virtual bet for B: "B below threshold_B", weight = w × splitFactor
```

For "underdog covers" (A-B ≤ X%), the excess flips: `excess = model_spread - spread_threshold`, and the virtual thresholds push A *down* and B *up*.

`splitFactor` (e.g. 0.5) controls how much of the spread signal each shooter receives, discounting for the ambiguity in which shooter is driving the spread.

(Since the MC samples come from normal distributions around each player's expected strength, the mean and median are effectively interchangeable here.)

### Why Spread-Derived Thresholds Are Necessary

A naive approach would place the virtual threshold at the model's median (P_model = 0.50) for every spread bet. This loses the odds signal: a near-certainty spread bet and a long-shot spread bet would produce the same posterior shift, despite carrying very different amounts of information.

With spread-derived thresholds, the P_model of each virtual market reflects the extremity of the spread claim:

**Long-odds spread "A-B ≥ 20%"** (model expects 7% spread, excess = 13%):

```
threshold_A = 0.85 + 0.065 = 0.915
threshold_B = 0.78 - 0.065 = 0.715

P_model("A above 91.5%") ≈ 0.12  (tail of A's distribution)
P_model("B below 71.5%") ≈ 0.15  (tail of B's distribution)
→ Posteriors shift substantially → large δ_A, δ_B → spread widens significantly
```

**Short-odds spread "A-B ≥ 1%"** (model expects 7% spread, excess = -6%):

```
threshold_A = 0.85 - 0.03 = 0.82
threshold_B = 0.78 + 0.03 = 0.81

P_model("A above 82%") ≈ 0.72  (easy side of A's distribution)
P_model("B below 81%") ≈ 0.68  (easy side of B's distribution)
→ Posteriors barely move → tiny δ_A, δ_B → spread barely changes
```

This correctly mirrors how the main Bayesian framework amplifies long-odds bets: a small P_model means `totalWeight` is large relative to `modelAlpha`, so the posterior shifts further from the model.

Key properties:

- **Long-odds spread bets push harder.** The virtual thresholds land in the tails, where P_model is small and the posterior shift is amplified — correctly, because the bettor is asserting something the model considers unlikely.
- **Short-odds spread bets barely move the line.** The thresholds are on the easy side of the distribution, confirming what the model already believes.
- **Directionally correct.** "Favorite covers" pushes A up and B down. "Underdog covers" does the opposite.
- **Combines with real percentage bets.** The virtual markets enter the same WLS optimization as direct percentage bets, naturally reconciling all evidence.
- **The max-logit-shift clamp** still protects against over-movement from extremely long-odds spread bets.

### Generating Spread Odds from Individual Deltas

To price a spread market "A beats B by ≥X%", compute δ_A and δ_B separately from their respective percentage evidence (including any virtual markets from spread bets), then evaluate the spread predicate on the shifted paired MC samples: for each trial i, shifted spread = (pctA[i] + δ_A) − (pctB[i] + δ_B); count how many trials satisfy the threshold. The MC samples are paired (same trial index = same simulated match); shifting each shooter's marginal by their δ preserves correlation. See the spread-odds path in the odds/wager pipeline for the actual implementation.

### Evidence Flow

All evidence about a shooter's strength converges into a single δ_pct, regardless of source:

- A direct percentage bet on A → contributes to A's δ_pct directly.
- A spread bet on A vs B → contributes to A's δ_pct (and B's) via virtual percentage markets at spread-derived thresholds.
- Multiple spread bets involving A (vs. different opponents) → all contribute to A's δ_pct, reinforcing the signal about A's strength.

This means a shooter who appears in several spread bets accumulates evidence about their individual performance, even if no one has placed a direct percentage bet on them.

### Worked Example

**Setup:** A expected at ~85%, B expected at ~78%. Model spread = 7%. N_eff = 100.

**Bet:** "A beats B by ≥15%", sharp player, weight = 1.8, splitFactor = 0.5.

This is a long-odds bet (model spread is 7%, bet claims ≥15%).

**Decomposition:**

```
excess = 0.15 - 0.07 = 0.08
threshold_A = 0.85 + 0.04 = 0.89
threshold_B = 0.78 - 0.04 = 0.74

w_A = 1.8 × 0.5 = 0.9
w_B = 1.8 × 0.5 = 0.9

Virtual market for A: "above 89%"
  P_model("A above 89%") ≈ 0.20  (in the upper tail of A's distribution)
  P_posterior = (0.20 × 100 + 0.9) / (100 + 0.9) = 20.9 / 100.9 = 0.2072

Virtual market for B: "below 74%"
  P_model("B below 74%") ≈ 0.22  (in the lower tail of B's distribution)
  P_posterior = (0.22 × 100 + 0.9) / (100 + 0.9) = 22.9 / 100.9 = 0.2270
```

The posteriors are meaningfully above P_model (relative shifts of ~3.6% and ~3.2%), producing non-trivial δ values. Compare to a short-odds spread bet on "A-B ≥ 1%" (excess = -0.06), which would place thresholds at 82% and 81% — well inside the fat part of each distribution (P_model ≈ 0.70), producing near-zero posterior shifts.

The δ optimizer for A finds a positive δ_A (A shifts upward). The δ optimizer for B finds a δ_B that shifts B downward. When pricing the spread market, the combined effect widens the spread: `δ_A + |δ_B|`.

### Worked Example: Underdog Covers

**Setup:** Same as above. A expected at ~85%, B expected at ~78%. Model spread = 7%. N_eff = 100.

**Bet:** "B covers (A-B ≤ 3%)", sharp player, weight = 1.8, splitFactor = 0.5.

This bettor thinks the spread is narrower than the model expects — B will perform closer to A than the 7% gap suggests.

**Decomposition (underdog covers: excess flips):**

```
excess = model_spread - spread_threshold = 0.07 - 0.03 = 0.04
threshold_A = mean_A - excess / 2 = 0.85 - 0.02 = 0.83
threshold_B = mean_B + excess / 2 = 0.78 + 0.02 = 0.80

w_A = 1.8 × 0.5 = 0.9
w_B = 1.8 × 0.5 = 0.9

Virtual market for A: "below 83%"
  P_model("A below 83%") ≈ 0.28  (the weaker side of A's distribution)
  P_posterior = (0.28 × 100 + 0.9) / (100 + 0.9) = 28.9 / 100.9 = 0.2864

Virtual market for B: "above 80%"
  P_model("B above 80%") ≈ 0.27  (the stronger side of B's distribution)
  P_posterior = (0.27 × 100 + 0.9) / (100 + 0.9) = 27.9 / 100.9 = 0.2765
```

Note the direction reversal compared to "favorite covers": the virtual market for A is now *below* the threshold (A performs worse than expected), and for B it's *above* (B performs better than expected). The δ optimizer for A finds a negative δ_A (A shifts downward), and for B finds a positive δ_B (B shifts upward). Both narrow the spread: `|δ_A| + δ_B`.

The posterior shifts here (~2.3% and ~2.4% relative) are smaller than in the favorite-covers example because the thresholds land closer to the model center (P_model ≈ 0.27-0.28 vs. 0.20-0.22), meaning this bet is less extreme relative to the model's expectations. A more aggressive underdog-covers bet like "A-B ≤ 0%" (the underdog wins outright) would push thresholds further into the tails and produce larger shifts.

### Open Questions

- **Split ambiguity.** The equal split (splitFactor = 0.5) assumes no knowledge of which shooter drives the spread. If individual percentage bets exist for one shooter, they anchor that shooter's δ, and the spread bet's contribution is additive. A more sophisticated split could use the relative uncertainty of the two shooters (the less-certain shooter gets more of the split), but this adds complexity for a small gain.
- **Double-counting.** If someone bets both "A above 90%" and "A beats B by ≥10%", both contribute to A's δ_pct. The percentage bet directly; the spread bet via the spread-derived virtual percentage market for A. This isn't exactly double-counting (the virtual market uses the spread-derived threshold, not 90%), but the two signals do carry correlated information. The splitFactor discount (0.5) provides some buffering.
- **Correlation distortion.** Shifting A and B's marginals independently slightly distorts the joint distribution. The MC samples capture the true correlation (e.g., both do well on the same stages); shifting each marginal treats the shifts as independent. For small δ values this is negligible. For large shifts, the spread probability may be slightly miscalibrated — but the δ values from bet evidence will be small in practice (see "The Core Problem" on liquidity).

## Appendix: Bettor Wager Exclusion (Anti-Arbitrage)

### The Arbitrage Opportunity

The compute-on-demand model creates an arbitrage opportunity for a bettor who has private information (or a strong opinion) about a shooter's performance. Suppose Player A believes competitor B will perform above model expectation:

1. Player A first places a bet in the **opposite** direction (e.g. "B below 70%"). This moves B's line down, but Player A's bet is locked at the original (model) odds.
2. Player A then places a bet in the **real** direction (e.g. "B above 85%"). Because their first bet shifted δ downward, the line for "B above 85%" is now more favorable than it would have been at model odds.

The result: Player A holds a down bet at model odds and an up bet at better-than-model odds — a possible net profit regardless of outcome.

### The Double-Down Scenario

There is a legitimate scenario that looks superficially similar: a player with amount-limited wagers who wants to place multiple bets in the **same** direction (e.g. max-size bet on "B above 85%", then a second max-size bet on "B above 85%"). In this case, the line **should** move to reflect their cumulative conviction. If we naively excluded all of the bettor's own prior wagers, the line would never move for repeat same-direction bettors, allowing them to place unlimited bets at model odds and diluting the conviction signal in odds movement.

### Solution: Direction-Based Exclusion

When computing δ for a subject on behalf of a specific bettor, exclude the bettor's own prior wagers that point in the **opposite direction** from the incoming bet. Keep wagers that point in the **same direction** — these represent the double-down case where line movement is desirable.

This requires determining the "direction" of each wager relative to the subject. The direction can be derived from prediction fields without any spread decomposition or Monte Carlo lookups:

**Percentage wagers:** Direction is the `abovePercentage` field directly. `true` = "up" (subject does better), `false` = "down".

**Spread wagers:** First determine whether the subject is the favorite or the underdog in the spread. Then:

```
signal_up = (subject is favorite) == favoriteCovers
```

- Subject is favorite, `favoriteCovers` = true → "up" (spread says the favorite outperforms)
- Subject is favorite, `favoriteCovers` = false → "down" (spread says the favorite underperforms)
- Subject is underdog, `favoriteCovers` = true → "down" (spread says the underdog falls behind)
- Subject is underdog, `favoriteCovers` = false → "up" (spread says the underdog outperforms)

This is the key advantage of the direction-based approach: spread direction is fully determined by `favoriteCovers` and the subject's role, without needing to compute the decomposed virtual percentage thresholds. The decomposition (which requires MC samples for both competitors) is only needed for the Bayesian calculation itself, not for the drop/keep decision.

**Place wagers:** Compare the midpoint of the place range to the model's expected finish (available from the MC samples already loaded for the subject). Midpoint better than model = "up", worse = "down".

**Cross-type comparisons** (e.g. incoming percentage vs. prior spread, or incoming spread vs. prior percentage) use the same direction derivation for each wager and compare.

### Exclusion Logic

For each of the bettor's own prior wagers on the subject:

1. Derive the direction of the prior wager for the subject.
2. Derive the direction of the incoming bet for the subject.
3. If directions **agree** → keep the prior wager (double-down; line should hold).
4. If directions **disagree** → exclude the prior wager (potential arbitrage).

For multi-leg wagers (parlays), all compatible legs must agree in direction to keep the wager. If any compatible leg points opposite to the incoming bet, the wager is excluded.

### Interaction with Caching

When wagers are excluded, the resulting δ is bettor-specific and must **not** be cached in the shared BayesianDelta table — it would poison the cache for other bettors who should see the full-evidence δ. Only deltas computed with the complete (unfiltered) wager list are cached. When the bettor has exclusions, δ is computed on demand and not persisted.

This means:

- A bettor with excluded wagers pays the recomputation cost each time they request odds. In practice this is negligible (the δ search is fast).
- Other bettors see the full-evidence δ (from cache or freshly computed with all wagers).
- If the bettor's excluded wagers happen to include the most recent one, the cache timestamp still reflects the most recent wager. The bettor skips the cache (exclusions exist); other bettors hit the cache normally.

### Limitations

**Conservative cross-type exclusion.** The direction check can produce false positives in cross-type cases. Example: a bettor first bets "B above 85%" (genuine belief B does well), then bets the spread "A beats B by ≥10%" (favorite covers). For subject B, the prior is "up" and the incoming spread's signal is "down" — the direction check excludes the prior bet. But this isn't actually exploitable: the prior bet on B *hurts* the spread odds for the bettor (B's line moves up, narrowing the gap), so there is no arbitrage incentive. Excluding the prior bet gives the bettor slightly more favorable spread odds than they would otherwise get — a small concession, not an exploit.

**No graded similarity.** The direction check is binary (same vs. opposite), not graded. Two same-direction bets at very different thresholds (e.g. "B above 60%" and "B above 95%") are treated identically. A future enhancement could use full similarity detection (see "Similarity Between Wagers") for the drop/keep decision, but this requires decomposing spread wagers into their virtual percentage thresholds — the expensive step we avoid here.

## Appendix: Place and Percentage (Single δ, Range Decomposition, Slope)

This appendix describes a **unified** design: a single δ in percentage space for each shooter. All place predictions are **range** predictions (e.g. 1st–10th). Place bets do not maintain a separate δ_place; they contribute evidence as percentage signals and are evaluated using the percentage–place slope at the range boundaries.

### Single δ in Percentage Space

There is only **δ_pct** (percentage points). Direct percentage bets, spread-derived virtual percentage markets (see previous appendix), and place-range-derived virtual percentage markets all feed into the same WLS optimizer. One δ per shooter; no separate place delta or cross-type propagation step.

Since certain regions of the result space may not have enough density in finishes to accurately calculate δ_pct, we retain all the calculation infrastructure for δ_place to use in those scenarios.

### All Place Predictions Are Range Predictions

Every place market is an interval [a, b] (e.g. 1st–10th: best place in range = 1, worst place in range = 10). There is no distinct “single place” market; the same mechanism handles all place markets.

### Using a Place Bet as Evidence

To use a place-range bet as evidence for the shared δ_pct:

1. **Map the range to percentage bounds.** For the shooter’s MC samples, determine the percentage that corresponds to the **best** place in the range (e.g. 1st) and the **worst** place in the range (e.g. 10th). For example: mean or median percentage among trials that finished at (or in a small band around) that place.
2. **Create two virtual percentage wagers** (same idea as spread decomposition):
   - "Below pct at **best** place in range" (e.g. worse than the percentage corresponding to 1st).
   - "Above pct at **worst** place in range" (e.g. better than the percentage corresponding to 10th).
   The bettor is betting the shooter finishes in the range, so both bounds are "for" the outcome.
3. **Split the bet weight** between the two virtual wagers (e.g. 0.5 each) so the single place bet does not get double weight in the objective.

These virtual wagers enter the same posterior and WLS objective as direct percentage bets and spread-derived percentage signals. Place evidence thus influences δ_pct directly; no separate place delta is computed or propagated unless sparse finishes require it.

### Evaluating a Place Bet (Probability Under δ_pct)

To compute P(shooter finishes in [a, b]) under the shifted distribution:

1. **Slope at top and bottom of range.** At the **best** place in the range (a) and the **worst** place (b), compute the empirical slope Δpct/Δplace from the MC data (e.g. sort trials by place; slope at position p ≈ (mean_pct at p−1 − mean_pct at p+1) / 2, or use a competitor predicted to finish near that place — see below).
2. **Convert δ_pct to effective place shift at each boundary.** At the bottom of the range: δ_place_at_a = δ_pct / slope_at_a. At the top: δ_place_at_b = δ_pct / slope_at_b. (Better percentage ⇒ better place, so a positive δ_pct corresponds to moving to a better place.)
3. **Evaluate the place predicate.** Use these effective place shifts to define the shifted range or to shift each sample’s place by a position-dependent amount, then count trials that fall in the shifted range. For example: for each trial at place_i, compute effective δ_place(place_i) from the slope at place_i (or interpolate between slope_at_a and slope_at_b), then shifted_place_i = place_i − δ_place(place_i); count trials where shifted_place is in [a, b].

So place markets are evaluated by converting the single percentage shift into a position-dependent place shift using the slope at the relevant positions, then counting as usual.

### Slope From a Nearby Competitor (Optional Refinement)

The shooter’s own MC samples may be sparse at a given place (e.g. few trials finishing exactly 10th). For a more stable slope at that position, **find a competitor whose expected finish is near that place** and use **their** MC samples to estimate Δpct/Δplace at that position. Their distribution is centered there, so many more trials land in that band and the slope estimate is more reliable. Use that slope when converting δ_pct ↔ place at the top or bottom of a place range for the shooter in question.

### Sparse Environments: Retaining Place-Based δ

In **sparse** environments (e.g. small fields, or positions where the shooter's MC samples are too thin for a stable slope), the position–percentage mapping is unreliable. We **retain place-based delta calculation** for use in those cases: compute a separate δ_place from place wagers only, and evaluate place markets by shifting place directly (as in the main body of the doc). When the field or the local sample count is dense enough, use the unified δ_pct path (place → two percentage signals, evaluate via slope); when sparse, fall back to δ_place so place evidence still moves place markets without relying on an unstable slope.

Caching still works as normal, with the added wrinkle that place range markets need to check for density before deciding on method.

### Summary

- **Evidence:** Place-range bet → two percentage signals (below pct at best place in range, above pct at worst place in range), split weight → same δ_pct optimizer as percentage and spread.
- **Evaluation:** Place range [a, b] → slope at a and b (shooter or nearby competitor) → δ_pct converted to place shift at each point → count trials in shifted range.
- No δ_place; no separate "unified propagation" step. Place and percentage are unified by expressing everything in percentage space and using the empirical slope only when evaluating a place predicate.

---

*This document represents a comprehensive plan for Bayesian odds adjustment. Implementation should proceed incrementally with extensive testing at each stage.*