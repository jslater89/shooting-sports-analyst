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

1. **Gathers related markets.** Find all previously accepted bets on the same shooter and market type (place or percentage). Spread bets are decomposed into percentage signals for each involved shooter.
2. **Computes a posterior for each market.** Each bet has a weight (based on conviction, bettor skill, and timing). For a given market, the sum of all bet weights acts as pseudo-observations in a Beta distribution update: the prior α comes from the Monte Carlo model probability × an effective sample size (N_eff), and the cumulative bet weight is added to α, pulling the posterior probability upward. Heavier total weight on a market (more bets, sharper bettors, larger wagers, closer to match day) moves the posterior further from the model.
3. **Finds a distribution shift (δ).** Search for the single δ that, when applied to all Monte Carlo trial results for this shooter, best fits the posteriors across all related markets simultaneously (weighted least squares). This δ represents "bets say this shooter is about δ units better/worse than the model thinks," where 'units' are places or percentage points, depending on market type.
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
N_eff = clamp(N_min, N_min + scale × log(1 + history_count), N_max)
α = P × N_eff
β = (1 − P) × N_eff
```

The logarithmic scaling reflects diminishing marginal information from additional matches: the 5th match tells you much more about a shooter's ability than the 50th, and the 50th tells you much more than the 200th. Under linear scaling, a 200-match veteran would get a dramatically stiffer prior than a 50-match regular; under log scaling, the difference is modest (`log(201) − log(51) ≈ 1.37`), which better reflects the actual reduction in uncertainty.

This also helps when a well-established shooter has an anomalous stretch (equipment change, injury). Under linear scaling, their deep history creates a near-immovable prior that sharp bettors can barely dent. Under log scaling, the prior is still informed but not a brick wall.

- **N_min**: floor so the prior is never useless (e.g. 20).
- **N_max**: cap so the prior is never rigid (e.g. 150).
- **scale**: controls how quickly N_eff grows with history. Tune so that "typical" veterans (30–60 matches) yield N_eff in the 50–100 range. With log scaling, scale values in the 10–25 range are reasonable (e.g. scale = 15: 30 matches → `15 × log(31) ≈ 51.5`, 60 matches → `15 × log(61) ≈ 61.6`).
- **useLogScale**: whether to apply log scaling (default true). Can be toggled off for comparison during backtesting.

Example (place market, one shooter):

```dart
int? matchCount = shooterRating.matchCount;  // from ShooterRating
double historyCount = (matchCount ?? 0).toDouble();
double scaledHistory = useLogScale ? log(1.0 + historyCount) : historyCount;
double nEff = (nMin + scale * scaledHistory).clamp(nMin.toDouble(), nMax.toDouble());
double alpha = modelP * nEff;
double beta = (1.0 - modelP) * nEff;
```

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
conviction_weight = bet_amount / player_bankroll
```

**Rationale**: A $100 bet from a $1000 bankroll (10%) shows higher conviction than $10 from $10,000 (0.1%).

**Range**: Typically 0.01 to 0.20 (1% to 20% of bankroll)

'Bankroll' is not always the correct measure. In some cases, players' wager amounts are limited by other factors (like membership tier or perhaps a future cap on wager size far from an event). In those cases, the correct conviction signal is bet amount divided by wager cap.

### 2. Player Skill Multiplier

```
player_accuracy = average_probability_of_correct_predictions
expected_accuracy = probability_of_average_odds
skill_multiplier = player_accuracy / expected_accuracy
```

**Examples**:
- 40% win rate (weak player): multiplier = 0.8 → downweight their bets
- 50% win rate (average): multiplier = 1.0 → neutral
- 70% win rate (sharp): multiplier = 1.4 → upweight their bets

**Minimum sample size**: Require at least 10 resolved bets before applying skill adjustment.

Naively counting successes vs. 50-50 overweights predictions from someone who wins 80% bets at an 80% rate, and underweights predictions from someone who wins 10% bets at a 20% rate—the latter should be the stronger signal.

### 3. Time Decay

```
days_until_match = (match_date - bet_date).days
time_decay = exp(-λ × days_until_match)
```

Where λ (lambda) controls decay rate. Suggested values:
- **λ = 0.01**: Slow decay (30 days out = 75% weight)
- **λ = 0.02**: Moderate decay (30 days out = 54% weight)
- **λ = 0.05**: Fast decay (30 days out = 22% weight)

**Rationale**: Bets placed closer to the match incorporate more recent information.

### 4. Combined Weight

```dart
double calculateBetWeight({
  required double betAmount,
  required double playerBankroll,
  required double playerAccuracy,
  required double daysUntilMatch,
  double baseWeight = 10.0,
  double lambda = 0.10,
}) {
  // Bet conviction (0.01 to 0.20 typically)
  double conviction = betAmount / playerBankroll;

  // Player skill (0.8 to 1.4 typically)
  double skillMultiplier = playerAccuracy / 0.50;

  // Time relevance (0.05 to 1.0)
  double timeDecay = exp(-lambda * daysUntilMatch);

  // Base weight: tunable parameter for overall sensitivity
  return conviction * skillMultiplier * timeDecay * baseWeight;
}
```

**baseWeight parameter**: Controls overall sensitivity to bets
- **baseWeight = 5**: Conservative (bets move odds slowly)
- **baseWeight = 10**: Moderate (recommended starting point)
- **baseWeight = 20**: Aggressive (bets move odds quickly)

## Step-by-Step Example (Conceptual)

The following illustrates how bet weight updates a **single market's** posterior (α, β) and thus that market's implied probability. In the full pipeline we do not persist per-market state: we compute posteriors for every market that has bets, find the single δ that best fits them (see "Cross-Market Adjustment via Distribution Shift"), then evaluate any requested market under the shifted distribution. This example shows the same weight math that feeds into that process, but since the combinatorics of the prediction game mean we will rarely have substantial action in the same market, the odds adjustment is a toy example of the concept rather than a final product.

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

| State | α | β | P(outcome) | Decimal Odds | Moneyline |
|-------|---|---|------------|--------------|-----------|
| Initial | 65.000 | 35 | 0.6500 | 1.462 | -217 |
| After Bet 1 | 65.009 | 35 | 0.6501 | 1.462 | -217 |
| After Bet 2 | 67.139 | 35 | 0.6573 | 1.445 | -224 |

The sharp player's late, large bet moved the line by 7 moneyline points.

## Cross-Market Adjustment via Distribution Shift

### The Problem

Player bets on "Max Michel 1st-3rd" but there's also a market for "Max Michel 1st-5th". These are related: if money suggests Max is more likely to finish 1st-3rd, he's probably also more likely to finish 1st-5th. When generating odds for any market, we need to incorporate evidence from all compatible previous bets on the same shooter. Compatible, at present, means either place, or percentage and spread. See the appendices for thoughts on unifying place and percentage.

### Architectural Model: Compute on Demand

We do **not** maintain persistent per-market states that are mutated as bets arrive. Instead, odds for any market are computed fresh from the raw bet history when needed. Accepted bets are never retroactively repriced — each bet is locked at the odds displayed at the time it was placed. But every accepted bet becomes evidence that shifts the line for all **future** odds generation involving its subject.

The flow when generating odds for a market:

1. Start with the MC model distribution for the shooter against the current field.
2. Gather all previously accepted bets on any compatible market for the same subject.
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

Prior bets for a shooter will typically span multiple distinct markets (the combinatorial space of place ranges, percentage thresholds, and spreads is large enough that exact duplicates are rare). Each market's cumulative posterior implies a shift. We find the single δ that best fits all compatible posteriors simultaneously, via weighted least squares:

```
// The below is expressed in terms of markets where each market might be several bets of
// different weights on the same predicate. The math works equivalently if we consider
// each bet individually, i.e. weight(B) for one bet instead of totalWeight(M) as the
// sum of bet weights.
For each market M that has bets:
  totalWeight(M) = Σ weight_i for all bets on M
  modelAlpha(M)  = P_model(M) × N_eff
  P_posterior(M) = (modelAlpha(M) + totalWeight(M)) / (N_eff + totalWeight(M))

Find δ that minimizes:
  Σ  totalWeight(M) × (P_shifted(M, Lδ) - P_posterior(M))²
over all markets M that have bets
```

`modelAlpha(M)` is simply the α of the Beta prior for market M: the model probability times the effective sample size. Together with `modelBeta(M) = (1 − P_model(M)) × N_eff`, these form the Beta(α, β) prior whose mean is P_model(M) and whose total confidence is N_eff (see "Principled Setting of α and β" above). `totalWeight(M)` is the sum of bet weights on market M, so markets with more/stronger bets get more say in determining δ. This is a 1D optimization over a smooth objective — golden section search works well.

```dart
/// Finds the distribution shift δ that best fits all market posteriors.
///
/// [sortedSamples]: MC finish positions, pre-sorted ascending.
/// [marketPosteriors]: for each market with bets, its posterior P and total bet weight.
/// [marketPredicates]: for each market, a function testing if a shifted sample satisfies it.
double findCumulativeShift({
  required List<double> sortedSamples,
  required Map<String, ({double posteriorP, double totalWeight})> marketPosteriors,
  required Map<String, bool Function(double)> marketPredicates,
  double searchLo = -30.0,
  double searchHi = 30.0,
}) {
  int N = sortedSamples.length;

  double objective(double delta) {
    double error = 0.0;
    for (var entry in marketPosteriors.entries) {
      var predicate = marketPredicates[entry.key]!;
      int count = 0;
      for (var sample in sortedSamples) {
        if (predicate(sample - delta)) count++;
      }
      double shiftedP = count / N;
      double diff = shiftedP - entry.value.posteriorP;
      error += entry.value.totalWeight * diff * diff;
    }
    return error;
  }

  // Golden section search (or ternary search) to minimize the objective
  double gr = (sqrt(5) + 1) / 2;
  double a = searchLo, b = searchHi;
  double c = b - (b - a) / gr;
  double d = a + (b - a) / gr;

  for (int i = 0; i < 50; i++) {
    if ((b - a).abs() < 0.001) break;
    if (objective(c) < objective(d)) {
      b = d;
    }
    else {
      a = c;
    }
    c = b - (b - a) / gr;
    d = a + (b - a) / gr;
  }
  return (a + b) / 2;
}
```

**Example:** Three bets on John Smith — one on 1st-10th (weight 2.13), one on 12th-16th (weight 0.8), and one on 1st-5th (weight 0.3). All three posteriors imply a shift toward better finishes. The golden section search finds the δ that best reconciles all three, weighted by bet strength.

**When posteriors conflict** (e.g. a bet on 1st-10th and a bet on 35th-40th pointing in opposite directions), the weighted least squares naturally compromises, with heavier-bet markets dominating.

**Note on fractional positions:** When δ = 1.5, a trial originally at 11th becomes 9.5th, which is inside the 1st-10th range. Use `threshold + 0.5` as the boundary (e.g. a sample at 10.5 or below counts as "10th or better") to keep the counting smooth.

### Generating Odds Under the Shifted Distribution

Once δ is computed, generating odds for any market is straightforward: count how many shifted samples satisfy the market's predicate.

```dart
/// Generates the adjusted probability for a requested market, incorporating
/// all prior bet evidence for this shooter.
double getAdjustedProbability({
  required List<double> sortedSamples,
  required double delta,
  required bool Function(double) satisfiesMarket,
  required double modelP,
  double maxLogitShift = 1.0,
}) {
  int N = sortedSamples.length;
  int count = 0;
  for (var sample in sortedSamples) {
    if (satisfiesMarket(sample - delta)) count++;
  }
  double shiftedP = count / N;

  return clampMovement(modelP, shiftedP, maxLogitShift: maxLogitShift);
}
```

This is the same computation whether the requested market has prior bets on it or not. A bet on 1st-10th naturally moves the odds for 12th-16th, for 1st-10th itself (line movement), and for 35th-40th — all from the same δ, all with the correct magnitude.

### Worked Example: Place Markets (End-to-End)

**Setup:** John Smith, model expects ~27.5th finish. N = 10,000 MC trials. N_eff = 100.

**Prior bets:**
- Bet A: "John Smith 1st-10th", sharp player, late, weight = 2.13
- Bet B: "John Smith 1st-5th", moderate player, weight = 0.5

**Step 1 — Compute posteriors for markets with bets:**
```
1st-10th: P_model = 0.012 → P_posterior = (0.012 × 100 + 2.13) / (100 + 2.13) = 0.0326
1st-5th:  P_model = 0.003 → P_posterior = (0.003 × 100 + 0.50) / (100 + 0.50) = 0.0080
```

Both posteriors point toward better finishes, so they're consistent.

**Step 2 — Find δ:** Golden section search minimizes the weighted error across both posteriors. Finds δ ≈ 1.8 positions (model expected ~27.5th, implied ~25.7th).

**Step 3 — Generate odds for any requested market under the shifted distribution:**

| Requested Market | P_model | P_shifted | Change |
|---|---|---|---|
| 1st-5th | 0.003 | 0.008 | +0.005 (line moved) |
| 1st-10th | 0.012 | 0.033 | +0.021 (line moved) |
| 12th-16th | 0.045 | 0.058 | **+0.013** |
| 20th-25th | 0.220 | 0.240 | **+0.020** (largest change) |
| 25th-30th | 0.280 | 0.272 | **-0.008** |
| 35th-40th | 0.110 | 0.098 | **-0.012** |

Key observations:

- **Line movement works naturally.** A new bettor asking for odds on 1st-10th or 1st-5th sees updated probabilities. Prior bets were the evidence that moved the line.
- **Direction is automatic.** Markets on the "better" side of the model center get positive shifts; markets on the "worse" side get negative. No direction heuristic needed.
- **Strength has the right shape.** The largest positive change is at 20th-25th — just on the "better" side of the model mode, where the PDF is densest. The bet targets (1st-10th, 1st-5th), despite having the direct evidence, have smaller absolute changes because the tail is thin (although the probabilites change more in relative terms).
- **Disjoint-but-same-side works correctly.** 12th-16th has no overlap with either bet range, but still gets a positive shift because the distribution shift moves mass into that range.
- **Works for any distribution shape.** Skewed, multimodal, heavy-tailed — the MC samples represent the actual distribution. The only caveat is that bets cannot add uncertainty or width; those come from the model and are not affected by the shift.

### Worked Example: Percentage Markets

**Setup:** Jane Doe, model expects ~75th percentile. N = 10,000 MC trials. N_eff = 100.

**Prior bets:**
- Bet A: "above 95%", sharp player, weight = 1.5
- Bet B: "above 90%", moderate player, weight = 0.4

**Step 1 — Compute posteriors:**
```
above 95%: P_model = 0.018 → P_posterior = (0.018 × 100 + 1.5) / (100 + 1.5) = 0.033
above 90%: P_model = 0.052 → P_posterior = (0.052 × 100 + 0.4) / (100 + 0.4) = 0.056
```

Both point upward — consistent.

**Step 2 — Find δ:** Golden section search finds δ ≈ 1.2 percentage points upward (model expected ~75%, implied ~76.2%).

**Step 3 — Generate odds for any requested market:**

| Requested Market | P_model | P_shifted | Change |
|---|---|---|---|
| Above 95% | 0.018 | 0.033 | +0.015 (line moved) |
| Above 90% | 0.052 | 0.072 | **+0.020** |
| Above 85% | 0.125 | 0.155 | **+0.030** |
| Above 80% | 0.290 | 0.325 | **+0.035** (largest!) |
| Below 70% | 0.195 | 0.172 | **-0.023** |
| Below 60% | 0.085 | 0.070 | **-0.015** |

**Above 80%** sees the largest change because it's near the model's mode where the PDF is densest. Below 60% gets a stronger penalty than below 70%, because it's further from the model center on the "wrong" side.

### Why This Replaces Proximity Heuristics

A linear proximity factor (increasing with distance from the model center toward the bet) gets the strength allocation systematically wrong:

| Target | True Change (from distribution shift) | Linear Proximity (old) |
|---|---|---|
| >80% (near model mode) | **+0.035** (largest) | 0.25 (weak) |
| >85% | +0.030 | 0.50 (moderate) |
| >90% | +0.020 | 0.75 (strong) |
| >95% (bet target) | +0.015 | 1.00 (strongest) |

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

The fix is to clamp symmetrically in **log-odds space**. The logit transform `logit(p) = ln(p / (1 − p))` maps probabilities to the real line, where a fixed-width band has uniform meaning across the probability range: a shift of 1 logit unit roughly doubles or halves the odds ratio, regardless of baseline probability.

```dart
double _logit(double p) => log(p / (1.0 - p));
double _sigmoid(double x) => 1.0 / (1.0 + exp(-x));

double clampMovement(double modelP, double shiftedP, {double maxLogitShift = 1.0}) {
  double modelLogit = _logit(modelP);
  double lower = _sigmoid(modelLogit - maxLogitShift);
  double upper = _sigmoid(modelLogit + maxLogitShift);
  return shiftedP.clamp(lower, upper);
}
```

The `maxLogitShift` parameter controls how far the odds can move. A value of 1.0 means the odds ratio can roughly double or halve. The allowed range in probability space:

| modelP | Allowed range | Absolute width |
|--------|---------------|----------------|
| 0.01   | [0.004, 0.027] | 0.023 |
| 0.05   | [0.019, 0.125] | 0.106 |
| 0.50   | [0.269, 0.731] | 0.462 |
| 0.95   | [0.875, 0.981] | 0.106 |
| 0.99   | [0.973, 0.996] | 0.023 |

Key properties:
- **Symmetric**: P = 0.05 and P = 0.95 get the same absolute width (0.106).
- **Long shots can move**: P = 0.01 gets a range of [0.004, 0.027], not the frozen [0.008, 0.012] of a linear 20% clamp.
- **Favorites can't exceed 1.0**: The sigmoid naturally stays in (0, 1).
- **Single tunable parameter**: `maxLogitShift` has uniform meaning across the probability range — "how many doublings/halvings of the odds ratio are allowed?"

Compare to the linear clamp (`maxMove = modelP × 0.20`):

| modelP | Log-odds range | Linear 20% range |
|--------|---------------|-------------------|
| 0.01   | [0.004, 0.027] | [0.008, 0.012] |
| 0.05   | [0.019, 0.125] | [0.040, 0.060] |
| 0.50   | [0.269, 0.731] | [0.400, 0.600] |
| 0.95   | [0.875, 0.981] | [0.760, 1.000] |

The linear clamp over-restricts long shots and over-permits near-certainties.

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

1. **MC sample ordering must be preserved** — trial indices must stay aligned across shooters so that spread predictions can compare shooter A's trial _i_ against shooter B's trial _i_. Sorting per-shooter samples by finish position or percentage would destroy this pairing. The samples are simply scanned in trial order.
2. **δ search** converges in ~15 iterations of golden section search (or ~15 iterations of binary search for single-market case). Each iteration scans the samples: O(N) per iteration, O(15N) total. For N = 10,000, this is ~150,000 comparisons.
3. **Evaluating P_shifted** for the requested market is one pass over the shifted samples: O(N).
4. **Sorted copies for binary search** — maintaining a sorted copy of each shooter's samples (separate from the trial-ordered originals) would allow O(log N) boundary lookups instead of O(N) linear scans for place and percentage markets, with the break-even at roughly log₂(N) queries (~14 for N = 12,500). Spread markets would still require linear scans on the paired data. At current sample sizes the linear scan completes in microseconds, so this is not worth implementing unless profiling shows the δ search is a bottleneck.
5. **Cache δ per shooter**: See "Caching δ Per Shooter" below.
6. **Index bets by subject**: Group accepted bets by shooter for fast lookup during odds generation.

### Caching δ Per Shooter

δ for a given shooter is a function of (all prior bets on that shooter, MC samples, N_eff) — none of which depend on the market being requested. This means δ can be computed once and reused for all market evaluations on that shooter until new evidence arrives.

Since δ entries are small (a double, a timestamp, and a few links) and rarely looked up, they belong in the database rather than an in-memory cache. This gives persistence across restarts, lets us link entries to the wagers and shooter ratings that produced them, and naturally accumulates a history for line-movement visualization.

**Schema:**

```dart
@collection
class ShooterDelta with DbShooterRatingEntity {
  Id id = Isar.autoIncrement;

  /// The δ value (distribution shift).
  double delta;

  @enumerated
  MarketType type;

  /// When this δ was computed.
  DateTime computedAt;

  /// The timestamp of the most recent bet included in this δ computation.
  DateTime lastBetTimestamp;

  /// The match prep this δ is associated with.
  final matchPrep = IsarLink<MatchPrep>();

  /// The prediction game this δ is associated with.
  final game = IsarLink<PredictionGame>();

  /// The wagers that contributed to this δ.
  final contributingWagers = IsarLinks<DbWager>();

  /// The IDs of the wagers that contributed to this δ.
  ///
  /// This allows fast lookup of deltas by wager.
  @Index()
  List<int> contributingWagerIds = [];

  @Index()
  String shooterKey;

  ShooterDelta({
    required this.delta,
    required this.computedAt,
    required this.lastBetTimestamp,
    required this.shooterKey,
  });
}

enum MarketType {
  place,
  percentage;
  // Spread bets are decomposed into percentage signals, so no separate
  // spread type is needed. See "Spread Bets as Percentage Signals."
  // Future: unified (place ↔ percentage propagation).
}
```

**Cache lookup flow:**

```
On odds request for shooter S in match M:
  entry = db.shooterDeltas
    .filter()
    .shooterKeyEqualTo(S)
    .sortByComputedAtDesc()
    .findFirstSync()

  if entry != null:
    latestBet = most recent accepted bet for S in M
    if latestBet == null || latestBet.created <= entry.lastBetTimestamp:
      → use entry.delta (cache hit)
    else:
      → recompute δ, write new entry (new bet invalidated it)
  else:
    → compute δ, write new entry
```

This reduces repeated odds requests (e.g. browsing a market list, or multiple users viewing the same shooter) to O(N) per market (one pass over MC samples to evaluate the predicate) rather than O(15N × M) to recompute δ each time.

**Invalidation:** No explicit invalidation is needed — the timestamp comparison handles staleness. Old entries stay in the DB as history. When the MC simulation is re-run (new registration set), either write a new δ entry (the next odds request will recompute against the new samples) or mark a simulation boundary for the line-movement chart.

**Line-movement visualization:**

Since every δ computation writes a new entry (rather than overwriting), the DB naturally accumulates a history of how δ evolved as bets arrived. To render a line-movement chart for a specific market:

1. Query all `ShooterDelta` entries for the shooter, ordered by `computedAt`.
2. For each entry, evaluate the market's predicate against the current MC samples shifted by that entry's δ.
3. Plot the resulting probability series over time.

Each entry's `contributingWagers` link lets the chart annotate which bet(s) caused each line movement. The `shooterRating` link provides context for tooltips (shooter name, rating at the time).

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

| Parameter | Recommended | Conservative | Aggressive | Description |
|-----------|-------------|--------------|------------|-------------|
| **Model Confidence** (α + β) | 50-100 | 100-200 | 25-50 | Set via N_eff from rating history (see "Principled Setting of α and β"); higher N_eff = less movement from bets. Do not tune α+β directly. |
| **N_eff Scale** | 15 | 20 | 10 | Multiplier on (log) history count when computing N_eff. Higher = stiffer prior for experienced shooters. |
| **N_eff Log Scale** | true | true | true | Use `log(1 + history)` instead of raw history count. Gives diminishing returns from deep history. |
| **Base Weight** | 10.0 | 5.0 | 20.0 | Overall bet impact scaling |
| **Time Decay λ** | 0.10 | 0.05 | 0.15 | Rate of early bet discounting |
| **Max Logit Shift** | 1.0 | 0.5 | 1.5 | Maximum movement in log-odds space (1.0 ≈ odds can double/halve). See "Maximum Odds Movement." |
| **Min Bets for Skill** | 10 | 20 | 5 | Minimum resolved bets to apply skill multiplier |

## Testing Strategy

### Unit Tests

1. **Weight calculation**: All factors (conviction, skill, time) combine properly
2. **Single-market δ**: Binary search converges to correct δ for known MC distributions. Verify with a simple uniform or Gaussian sample set where the answer is analytically known.
3. **Multi-market δ**: Golden section search finds the δ that best fits multiple market posteriors simultaneously. Verify with consistent and conflicting posteriors.
4. **Cross-market direction**: Same-subject markets get correct sign (positive for same-side, negative for opposite-side). Verify that disjoint-but-same-side ranges get positive changes (e.g. bet on 1st-10th increases P for 12th-16th when model expects ~27th).
5. **Cross-market shape**: Probability changes peak near the model mode, not in the tail. For a symmetric distribution, the largest change should be near the model center, not near the bet target.
6. **Line movement**: A bet on a market shifts that same market's odds for the next request.
7. **Bounds checking**: Probabilities stay in [0, 1], max movement enforced
8. **Voiding**: Voiding a bet and regenerating odds returns to model probabilities

### Integration Tests

1. **Multiple bets, same market**: Cumulative bet weights produce a single larger δ. Verify equivalent to processing bets individually.
2. **Multiple bets, different markets**: δ optimization reconciles multiple posteriors. Verify direction consistency.
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

## Appendix: Code Snippets

Snippets below are illustrative. Production should store δ in the database (ShooterDelta) per "Caching δ Per Shooter"; the OddsGenerator snippet uses an in-memory map for brevity. For weight calculation, `player` is the wager's user (e.g. `wager.user.value`) and `matchDate` comes from the wager's match context (e.g. `wager.matchPrep.value?.date` or equivalent).

### Complete Weight Calculation

```dart
double calculateBetWeight({
  required DbWager wager,
  required PredictionGamePlayer player,  // e.g. wager.user.value
  required DateTime matchDate,             // from wager's match prep / game context
  required double baseWeight,
  required double lambda,
  int minBetsForSkill = 10,
}) {
  // 1. Bet conviction
  double conviction = wager.amount / player.balance;
  conviction = conviction.clamp(0.01, 0.50);  // cap at 50% of bankroll

  // 2. Player skill
  var resolvedWagers = player.wagers
      .filter()
      .not().statusEqualTo(DbWagerStatus.pending)
      .not().statusEqualTo(DbWagerStatus.voided)
      .findAllSync();

  double skillMultiplier = 1.0;
  if (resolvedWagers.length >= minBetsForSkill) {
    int won = resolvedWagers.where((w) => w.status == DbWagerStatus.won).length;
    double accuracy = won / resolvedWagers.length;
    skillMultiplier = accuracy / 0.50;
    skillMultiplier = skillMultiplier.clamp(0.5, 2.0);  // cap at 0.5x to 2.0x
  }

  // 3. Time decay
  double daysUntilMatch = matchDate.difference(wager.created).inDays.toDouble();
  double timeDecay = exp(-lambda * daysUntilMatch);

  // 4. Combine
  return conviction * skillMultiplier * timeDecay * baseWeight;
}
```

### Complete Odds Generation Function

Conceptually; production should persist δ in ShooterDelta (DB) and invalidate by lastBetTimestamp as in "Caching δ Per Shooter."

```dart
class OddsGenerator {
  /// MC samples per shooter, pre-sorted ascending.
  Map<String, List<double>> sortedFinishSamples = {};
  Map<String, List<double>> sortedPercentageSamples = {};

  /// Cached δ per shooter (illustrative; use DB ShooterDelta in production). Invalidate when a new bet is accepted for that shooter.
  Map<String, double> _cachedDelta = {};

  /// Generates adjusted odds for a requested market, incorporating all prior bets.
  PredictionProbability generateOdds({
    required DbPrediction requestedMarket,
    required List<DbWager> priorBets, // all accepted, non-voided bets for this subject
    required double nEff,             // from shooter rating history
    required double houseEdge,
    double maxLogitShift = 1.0,
    double baseWeight = 10.0,
    double lambda = 0.10,
  }) {
    String shooterKey = requestedMarket.target.memberNumber;
    List<double> samples = _getSamples(requestedMarket, shooterKey);
    int N = samples.length;

    // Model probability (no bet evidence)
    int modelCount = 0;
    for (var sample in samples) {
      if (_satisfies(sample, requestedMarket)) modelCount++;
    }
    double modelP = modelCount / N;

    if (priorBets.isEmpty) {
      return PredictionProbability(modelP, houseEdge: houseEdge);
    }

    // Compute δ (use cache if available)
    double delta = _cachedDelta[shooterKey] ??
        _computeDelta(priorBets, samples, N, nEff, baseWeight, lambda);
    _cachedDelta[shooterKey] = delta;

    // Evaluate P under the shifted distribution
    int shiftedCount = 0;
    for (var sample in samples) {
      double shifted = _applyShift(sample, delta, requestedMarket);
      if (_satisfies(shifted, requestedMarket)) shiftedCount++;
    }
    double shiftedP = shiftedCount / N;

    double adjustedP = clampMovement(modelP, shiftedP, maxLogitShift: maxLogitShift);

    return PredictionProbability(adjustedP, houseEdge: houseEdge);
  }

  /// Computes the cumulative δ from all prior bets for a shooter.
  double _computeDelta(
    List<DbWager> bets,
    List<double> samples,
    int N,
    double nEff,
    double baseWeight,
    double lambda,
  ) {
    // Group bets by market and sum weights
    var marketWeights = <String, ({DbPrediction prediction, double totalWeight})>{};

    for (var wager in bets) {
      var prediction = wager.legs.first;
      String key = _marketKey(prediction);
      double weight = calculateBetWeight(
        wager: wager,
        player: wager.player,
        matchDate: wager.matchDate,
        baseWeight: baseWeight,
        lambda: lambda,
      );

      if (marketWeights.containsKey(key)) {
        var existing = marketWeights[key]!;
        marketWeights[key] = (
          prediction: existing.prediction,
          totalWeight: existing.totalWeight + weight,
        );
      }
      else {
        marketWeights[key] = (prediction: prediction, totalWeight: weight);
      }
    }

    // Compute posterior for each market, then find best-fit δ
    var posteriors = <String, ({double posteriorP, double totalWeight})>{};
    for (var entry in marketWeights.entries) {
      double modelP = _countSatisfying(samples, entry.value.prediction) / N;
      double posteriorP = (modelP * nEff + entry.value.totalWeight) /
          (nEff + entry.value.totalWeight);
      posteriors[entry.key] = (
        posteriorP: posteriorP,
        totalWeight: entry.value.totalWeight,
      );
    }

    return findCumulativeShift(
      sortedSamples: samples,
      marketPosteriors: posteriors,
      marketPredicates: {
        for (var entry in marketWeights.entries)
          entry.key: (double v) => _satisfies(v, entry.value.prediction),
      },
    );

  int _countSatisfying(List<double> samples, DbPrediction p) {
    int count = 0;
    for (var s in samples) {
      if (_satisfies(s, p)) count++;
    }
    return count;
  }

  List<double> _getSamples(DbPrediction p, String shooterKey) {
    switch (p.type) {
      case DbPredictionType.place:
        return sortedFinishSamples[shooterKey]!;
      case DbPredictionType.percentage:
        return sortedPercentageSamples[shooterKey]!;
      case DbPredictionType.spread:
        return sortedFinishSamples[shooterKey]!;
    }
  }

  double _applyShift(double sample, double delta, DbPrediction p) {
    return sample - delta * _shiftSign(p);
  }

  double _shiftSign(DbPrediction p) {
    switch (p.type) {
      case DbPredictionType.place:
        return 1.0;  // positive δ → subtract from finish → better finish
      case DbPredictionType.percentage:
        return -1.0; // positive δ → add to percentage → higher percentage
      case DbPredictionType.spread:
        throw ArgumentError("Spread bets should be decomposed into percentage "
            "signals before δ computation. See 'Spread Bets as Percentage Signals'.");
    }
  }

  bool _satisfies(double value, DbPrediction p, {int? fieldSize}) {
    switch (p.type) {
      case DbPredictionType.place:
        if(value < 0.5) value = 0.5;
        if(fieldSize != null && value > fieldSize + 0.5) value = fieldSize + 0.5;
        return value >= (p.bestPlace! - 0.5) && value <= (p.worstPlace! + 0.5);
      case DbPredictionType.percentage:
        if(value < 0) value = 0;
        if(value > 1) value = 1;
        if (p.abovePercentage) return value >= p.percentage!;
        return value < p.percentage!;
      case DbPredictionType.spread:
        throw ArgumentError("Spread bets should be decomposed into percentage "
            "signals before δ computation. See 'Spread Bets as Percentage Signals'.");
    }
  }

  String _marketKey(DbPrediction p) {
    return "${p.target.memberNumber}_${p.type}_"
           "${p.bestPlace}_${p.worstPlace}_${p.percentage}";
  }

  void invalidateCache(String shooterKey) {
    _cachedDelta.remove(shooterKey);
  }
}
```

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

To price a spread market "A beats B by ≥X%", compute δ_A and δ_B separately from their respective percentage evidence (including any virtual markets from spread bets), then evaluate the spread predicate on the shifted paired MC samples:

```dart
double getSpreadProbability({
  required List<double> pctSamplesA,
  required List<double> pctSamplesB,
  required double deltaA,
  required double deltaB,
  required double spreadThreshold,
  required bool favoriteCovers,
}) {
  int N = pctSamplesA.length;
  int count = 0;
  for (int i = 0; i < N; i++) {
    double shiftedSpread = (pctSamplesA[i] + deltaA) - (pctSamplesB[i] + deltaB);
    if (favoriteCovers ? shiftedSpread >= spreadThreshold : shiftedSpread <= spreadThreshold) {
      count++;
    }
  }
  return count / N;
}
```

The MC samples are already paired (each trial simulates the full match), so `pctSamplesA[i]` and `pctSamplesB[i]` are from the same simulated match. Shifting each shooter's marginal by their respective δ and evaluating the spread preserves the correlation structure.

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

## Appendix: Unified Signal Propagation (Place ↔ Percentage)

### Motivation

With spread bets already decomposed into percentage signals (see previous appendix), the remaining cross-type gap is between **place** and **percentage**. These are computed as separate δ values (δ_place in position units, δ_pct in percentage-point units), but both describe the same underlying reality: a shooter's performance. A place bet on "A finishes 1st-10th" carries information about A's percentage finish, because finishing 20th instead of 26th *necessarily* means a better percentage than the model predicted for 26th place. The question is whether we can let place evidence inform percentage δ and vice versa.

### The Cross-Domain Mapping Problem

The MC trials are the bridge. Each trial for shooter A has both a finish position and a percentage:

```
Trial 1: finished 23rd, 78.2%
Trial 2: finished 31st, 71.5%
Trial 3: finished 18th, 82.1%
...
```

These are jointly sampled — a trial where A finishes 18th also has a specific percentage that's consistent with finishing 18th in that simulated field. However, the mapping from percentage to place (and vice versa) depends on the entire field's performance in each trial. We don't store the full N_shooters × N_trials matrix, so we can't do the cross-domain lookup directly.

What we *can* observe: after computing δ_place from place bets, the shifted finish distribution has a different mean position. The relationship between position and percentage is encoded in the MC samples — across all 10,000 trials, there's an empirical correlation between finish position and percentage. We can estimate the implied percentage shift from the position shift using this correlation. Note that this mapping is only reliable for reasonably dense fields — in a 10-person match, the position-to-percentage relationship is sparse and noisy (a 1-position shift could correspond to anywhere from 0.5% to 10% depending on who's nearby), so the implied percentage shift would not be trustworthy. In larger fields (50+), the denser packing of competitors makes the empirical correlation much more stable.

### Approximate Conversion via Empirical Slope

Sort the MC trials by finish position. The empirical slope `Δpct/Δplace` around the model's expected finish gives the local conversion factor:

```
slope ≈ (mean_pct_at_position(model_place - 1) - mean_pct_at_position(model_place + 1)) / 2
implied_δ_pct ≈ δ_place × slope
```

For a shooter expected at ~26th, if the samples show that moving from 27th to 25th corresponds to a ~1.5 percentage-point increase, then `slope ≈ 0.75 pct/position`, and a δ_place of 2 implies δ_pct ≈ 1.5.

This is approximate (the slope varies across the distribution, and we're using a linear approximation), but for the small δ values produced by bet evidence, the linear regime is sufficient.

### When It Matters

Unified propagation is most valuable when:

- A shooter has bets across both place and percentage types — the evidence reinforces.
- A shooter has many place bets but someone requests a percentage market (or vice versa).
- Combined with spread decomposition, a shooter has place bets, percentage bets, and appears in spread bets — all three converge into a single δ_pct.

It matters less when bets are sparse or concentrated in a single type, since there's nothing to propagate across.

### Recommendation

Start with separate δ_place and δ_pct (plus spread decomposition into δ_pct). The cross-type propagation is a refinement that can be added later if backtesting shows meaningful information loss from keeping the types independent. The empirical-slope conversion is cheap to compute but adds a layer of approximation; validate against known MC distributions before relying on it, and keep the standalone mechanisms around for sparse fields.

### Open Questions

- **Mapping fidelity.** The slope approximation is linear; the true relationship may be nonlinear, especially in the tails. With 10,000 trials this is likely fine for small δ, but worth validating.
- **Double-counting.** If someone places both a place bet and a percentage bet on the same shooter, and unified propagation converts the place evidence into a percentage signal, the percentage δ would see both the direct percentage bet and the converted place signal. A conservative approach: discount the converted signal by a factor < 1 (e.g. 0.5×).
- **Computational cost.** Computing the empirical slope is one pass over sorted MC samples: O(N). The unified conversion is O(1) on top of the per-type δ searches. Negligible cost.

---

*This document represents a comprehensive plan for Bayesian odds adjustment. Implementation should proceed incrementally with extensive testing at each stage.*
