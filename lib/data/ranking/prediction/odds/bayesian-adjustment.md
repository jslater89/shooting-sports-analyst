# Bayesian Odds Adjustment for Prediction Game

## Overview

This document describes a Bayesian approach for adjusting betting odds based on player wagering activity, designed for the sparse liquidity environment of practical shooting sports betting.

## The Core Problem

In traditional sports betting, odds follow the money through simple supply/demand mechanics. With millions of dollars wagered, markets self-correct through liquidity. However, in practical shooting:

- **Low liquidity**: Few bets per specific market
- **Fragmented markets**: Hundreds of possible markets (any shooter, any place range, any percentage)
- **No exact market matching**: "Max Michel 1st-3rd" vs "Max Michel 1st-5th" are similar but distinct
- **Information signals**: Each bet carries information about the true probability

**Solution**: Use Bayesian updating to treat each bet as evidence that updates our probability estimates in a principled way.

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
N_eff = clamp(N_min, N_min + scale × history_count, N_max)
α = P × N_eff
β = (1 − P) × N_eff
```

- **N_min**: floor so the prior is never useless (e.g. 20).
- **N_max**: cap so the prior is never rigid (e.g. 150).
- **scale**: so that "typical" veterans yield N_eff in the 50–100 range (tune from backtests).

Example (place market, one shooter):

```dart
int? matchCount = shooterRating.matchCount;  // from ShooterRating
double historyCount = (matchCount ?? 0).toDouble();
double nEff = (nMin + scale * historyCount).clamp(nMin.toDouble(), nMax.toDouble());
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

## Bet Weighting Function

Not all bets carry equal information. The weight depends on:

### 1. Bet Size Relative to Bankroll

```
conviction_weight = bet_amount / player_bankroll
```

**Rationale**: A $100 bet from a $1000 bankroll (10%) shows higher conviction than $10 from $10,000 (0.1%).

**Range**: Typically 0.01 to 0.20 (1% to 20% of bankroll)

### 2. Player Skill Multiplier

```
player_accuracy = won_bets / total_resolved_bets
expected_accuracy = 0.50  // baseline for random player
skill_multiplier = player_accuracy / expected_accuracy
```

**Examples**:
- 40% win rate (weak player): multiplier = 0.8 → downweight their bets
- 50% win rate (average): multiplier = 1.0 → neutral
- 70% win rate (sharp): multiplier = 1.4 → upweight their bets

**Minimum sample size**: Require at least 10 resolved bets before applying skill adjustment.

### 3. Time Decay

```
days_until_match = (match_date - bet_date).days
time_decay = exp(-λ × days_until_match)
```

Where λ (lambda) controls decay rate. Suggested values:
- **λ = 0.05**: Slow decay (30 days out = 22% weight)
- **λ = 0.10**: Medium decay (30 days out = 5% weight)
- **λ = 0.15**: Fast decay (30 days out = 1% weight)

**Rationale**: Bets placed closer to the match incorporate more recent information (form, injuries, practice scores).

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

## Step-by-Step Example

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

Player bets on "Max Michel 1st-3rd" but there's also a market for "Max Michel 1st-5th". These are related: if money suggests Max is more likely to finish 1st-3rd, he's probably also more likely to finish 1st-5th. When generating odds for any market, we need to incorporate evidence from all previous bets on the same shooter.

### Architectural Model: Compute on Demand

We do **not** maintain persistent per-market states that are mutated as bets arrive. Instead, odds for any market are computed fresh from the raw bet history when needed. Accepted bets are never retroactively repriced — each bet is locked at the odds displayed at the time it was placed. But every accepted bet becomes evidence that shifts the line for all **future** odds generation, including for the same market (standard line movement).

The flow when generating odds for a market:

1. Start with the MC model distribution for the shooter.
2. Gather all previously accepted bets on any market for the same subject.
3. Compute the cumulative implied distribution shift (δ) from those bets.
4. Evaluate P(requested market) under the shifted distribution.
5. Apply house edge → display odds.

If the bettor accepts, their bet joins the evidence pool for all future odds.

### Market Linking: Same Subject

We do **not** need a continuous similarity function to decide *whether* to consider a bet. Same subject is sufficient:

- **Place or percentage on one shooter:** same shooter (e.g. same `memberNumber`) links all that shooter's bets.
- **Spread:** same two shooters (target + underdog) link spread bets.

### The Key Insight

A bet is not just evidence about one specific outcome range — it is evidence that the **entire finish distribution is shifted** in a particular direction. A bet on "John Smith 1st-10th" at long odds when the model expects him at ~27th doesn't just say "1st-10th is more likely." It says "the true distribution is shifted toward better finishes than the model thinks."

This shift affects every market for that shooter. The question is: by how much?

A naive approach would use heuristics (overlap, proximity to model center, odds-based multipliers) to estimate the effect on each market. But these heuristics get the shape systematically wrong. The actual probability change from a distribution shift peaks near the **center of the distribution** (where the PDF is densest), not in the tails. A linear proximity factor that increases with distance from the model center over-weights tail markets and under-weights the markets that are actually most affected.

Since the Monte Carlo simulation data is available during odds generation, we can compute the exact effect by shifting the MC samples directly. This replaces direction heuristics, proximity factors, and odds multipliers with a single, principled calculation.

### Computing the Cumulative Distribution Shift (δ)

The Monte Carlo simulation produces N samples (e.g. 10,000) for each shooter. For a place market, each sample is a finish position:

```
Trial 1: finished 23rd
Trial 2: finished 31st
Trial 3: finished 18th
...
Trial 10000: finished 27th
```

The model probability for any prediction is just a count: `P_model(1st-10th) = (trials finishing 1st-10th) / 10000`.

We model the cumulative bet evidence as a **location shift**: slide every sample by a constant δ.

```
shifted_finish(trial_i) = original_finish(trial_i) - δ    // for place (lower = better)
shifted_pct(trial_i)    = original_pct(trial_i) + δ       // for percentage (higher = better)
```

Prior bets for a shooter will typically span multiple distinct markets (the combinatorial space of place ranges, percentage thresholds, and spreads is large enough that exact duplicates are rare). Each market's cumulative posterior implies a shift. We find the single δ that best fits all posteriors simultaneously, via weighted least squares:

```
For each market M that has bets:
  totalWeight(M) = Σ weight_i for all bets on M
  P_posterior(M) = (modelAlpha(M) + totalWeight(M)) / (N_eff + totalWeight(M))

Find δ that minimizes:
  Σ  totalWeight(M) × (P_shifted(M, δ) - P_posterior(M))²
over all markets M that have bets
```

where `totalWeight(M)` is the sum of bet weights on market M, so markets with more/stronger bets get more say in determining δ. This is a 1D optimization over a smooth objective — golden section search works well.

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
  double maxMovementFraction = 0.20,
}) {
  int N = sortedSamples.length;
  int count = 0;
  for (var sample in sortedSamples) {
    if (satisfiesMarket(sample - delta)) count++;
  }
  double shiftedP = count / N;

  double maxMove = modelP * maxMovementFraction;
  return shiftedP.clamp(modelP - maxMove, modelP + maxMove);
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

- **Line movement works naturally.** A new bettor asking for odds on 1st-10th or 1st-5th sees updated probabilities. Their bets were the evidence that moved the line.
- **Direction is automatic.** Markets on the "better" side of the model center get positive shifts; markets on the "worse" side get negative. No direction heuristic needed.
- **Strength has the right shape.** The largest positive change is at 20th-25th — just on the "better" side of the model mode, where the PDF is densest. The bet targets (1st-10th, 1st-5th), despite having the direct evidence, have smaller absolute changes because the tail is thin.
- **Disjoint-but-same-side works correctly.** 12th-16th has no overlap with either bet range, but still gets a positive shift because the distribution shift moves mass into that range.
- **Works for any distribution shape.** Skewed, multimodal, heavy-tailed — the MC samples represent the actual distribution.

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

Protect against over-adjustment. After computing P_shifted from the shifted MC distribution, clamp the movement relative to the model probability:

```dart
double clampMovement(double modelP, double shiftedP, {double maxMovementFraction = 0.20}) {
  double maxMove = modelP * maxMovementFraction;
  return shiftedP.clamp(modelP - maxMove, modelP + maxMove);
}
```

**Example**: Model says P = 0.60
- Maximum adjusted probability: 0.72 (60% + 20%)
- Minimum adjusted probability: 0.48 (60% - 20%)

### Exposure Limits

Track total exposure and throttle odds movement when at risk:

```dart
class ExposureManager {
  double calculateExposure(List<DbWager> openWagers) {
    double totalExposure = 0.0;

    for (var wager in openWagers) {
      double potentialPayout = wager.payout();
      double exposure = potentialPayout - wager.amount;
      totalExposure += exposure;
    }

    return totalExposure;
  }

  double getExposureMultiplier(double exposure, double houseBalance) {
    double exposureRatio = exposure / houseBalance;

    // No throttling under 10% exposure
    if (exposureRatio < 0.10) return 1.0;

    // Linear throttling from 10% to 50% exposure
    if (exposureRatio < 0.50) {
      return 1.0 - (exposureRatio - 0.10) * 2.0;  // 1.0 down to 0.2
    }

    // Heavy throttling above 50%
    return 0.2;
  }
}
```

Apply to bet weight:
```dart
double adjustedWeight = baseWeight * exposureMultiplier;
```

### Decay Over Time

The bet weighting function already includes time decay (bets placed further from the match get lower weight). In the compute-on-demand model, this decay is applied naturally when bet weights are computed during odds generation — old bets automatically contribute less evidence to δ as the match approaches.

At match start, all bets become irrelevant (the match is happening). No explicit reset is needed; the time decay drives old bets' weights toward zero.

## Implementation Considerations

### Data Storage

No persistent per-market Bayesian state is needed. The inputs to odds generation are:

1. **MC samples per shooter** (pre-sorted by finish position and by percentage), generated at simulation time.
2. **Accepted bet history** — each bet stores its market (prediction), bet weight, and acceptance timestamp.
3. **N_eff per shooter** — derived from rating history (see "Principled Setting of α and β").

Odds are computed from scratch on demand. Caching δ per shooter is optional (invalidate when a new bet for that shooter is accepted).

### Bet Removal/Voiding

Since odds are computed from the raw bet history, voiding a bet is trivial: mark it as voided so it's excluded from future odds generation. No state to reverse, no floating-point drift. The next odds request for that shooter will naturally reflect the reduced evidence.

### Performance Optimization

The compute-on-demand model recomputes δ each time odds are requested, but the cost is modest:

1. **Pre-sort MC samples** by finish position (and by percentage) per shooter at simulation time.
2. **δ search** converges in ~15 iterations of golden section search (or ~15 iterations of binary search for single-market case). Each iteration scans the sorted samples: O(N) per iteration, O(15N) total. For N = 10,000, this is ~150,000 comparisons.
3. **Evaluating P_shifted** for the requested market is one pass over the shifted samples: O(N).
4. **Cache δ per shooter**: Since δ only changes when a new bet is accepted for that shooter, cache the result and invalidate on new bets. This reduces repeated odds requests (e.g. browsing a market list) to O(N) per market rather than recomputing δ each time.
5. **Index bets by subject**: Group accepted bets by shooter for fast lookup during odds generation.

## Tunable Parameters Summary

| Parameter | Recommended | Conservative | Aggressive | Description |
|-----------|-------------|--------------|------------|-------------|
| **Model Confidence** (α + β) | 50-100 | 100-200 | 25-50 | Higher = less movement from bets. Prefer setting via N_eff from rating history (see "Principled Setting of α and β"). |
| **Base Weight** | 10.0 | 5.0 | 20.0 | Overall bet impact scaling |
| **Time Decay λ** | 0.10 | 0.05 | 0.15 | Rate of early bet discounting |
| **Max Movement** | 20% | 10% | 30% | Maximum probability shift from model P |
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
6. **Time progression**: Old bets decay as match approaches

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

### Complete Weight Calculation

```dart
double calculateBetWeight({
  required DbWager wager,
  required PredictionGamePlayer player,
  required DateTime matchDate,
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

```dart
class OddsGenerator {
  /// MC samples per shooter, pre-sorted ascending.
  Map<String, List<double>> sortedFinishSamples = {};
  Map<String, List<double>> sortedPercentageSamples = {};

  /// Cached δ per shooter. Invalidate when a new bet is accepted for that shooter.
  Map<String, double> _cachedDelta = {};

  /// Generates adjusted odds for a requested market, incorporating all prior bets.
  PredictionProbability generateOdds({
    required DbPrediction requestedMarket,
    required List<DbWager> priorBets, // all accepted, non-voided bets for this subject
    required double nEff,             // from shooter rating history
    required double houseEdge,
    double maxMovementFraction = 0.20,
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

    double maxMove = modelP * maxMovementFraction;
    double adjustedP = shiftedP.clamp(modelP - maxMove, modelP + maxMove);

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
        return 1.0;
    }
  }

  bool _satisfies(double value, DbPrediction p) {
    switch (p.type) {
      case DbPredictionType.place:
        return value >= (p.bestPlace! - 0.5) && value <= (p.worstPlace! + 0.5);
      case DbPredictionType.percentage:
        if (p.abovePercentage) return value >= p.percentage!;
        return value < p.percentage!;
      case DbPredictionType.spread:
        // TODO: implement spread satisfaction check
        throw UnimplementedError();
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

## Appendix: Deriving Spread Odds from Individual Percentage Signals

### The Opportunity

A spread prediction like "A beats B by ≥5%" is fundamentally a claim about the *difference* between two shooters' percentage finishes. We may have direct evidence about that spread from prior spread bets on the same pair. But we may also have indirect evidence: separate percentage bets on shooter A and shooter B individually. A bet on "A above 90%" and a bet on "B below 70%" both imply that A's margin over B is likely larger than the model thinks — even though neither bet mentions the spread explicitly.

### Sketch of the Approach

The MC simulation already produces paired samples — each trial has a finish percentage for every shooter. So for shooters A and B, we have 10,000 paired (pctA, pctB) tuples, from which we can derive 10,000 spread samples: `spreadSample_i = pctA_i - pctB_i`.

**Direct spread evidence** works the same as place or percentage: prior spread bets on the A-vs-B pair produce posteriors, we find a δ_spread that shifts the spread samples to match, and we evaluate the requested spread market under the shifted spread distribution.

**Indirect evidence from individual percentage bets** is the interesting part. Bets on A's percentage imply a δ_A (shift in A's percentage distribution). Bets on B's percentage imply a δ_B. These individual shifts propagate to the spread:

```
shifted_spread_i = (pctA_i + δ_A) - (pctB_i + δ_B)
                 = spreadSample_i + (δ_A - δ_B)
```

So the net effect on the spread is `δ_A - δ_B`. If bets say A is better than the model thinks (δ_A > 0) and B is worse (δ_B < 0), the spread widens by δ_A + |δ_B|. If both are shifted upward, the spread effect partially cancels.

### Combining Direct and Indirect Evidence

When generating odds for a spread market on A vs B:

1. Compute δ_A from all prior percentage bets on A (the standard golden section search).
2. Compute δ_B from all prior percentage bets on B.
3. Compute δ_spread_direct from all prior spread bets on the A-vs-B pair.
4. The total spread shift is some combination of the direct and indirect signals.

The simplest combination: `δ_spread_total = δ_spread_direct + (δ_A - δ_B)`. This treats the individual percentage shifts and the direct spread evidence as independent, which is approximately correct when the bettors placing percentage bets and spread bets are different people with different information.

A more careful combination would use the same weighted-least-squares framework, fitting a single δ_spread to the posteriors from both direct spread bets *and* the implied spread shift from individual percentage posteriors. The individual percentage evidence would enter as an additional constraint with weight proportional to the total bet weight behind δ_A and δ_B.

### Open Questions

- **Double-counting.** If someone bets on "A above 90%" and also on "A beats B by ≥10%", both bets carry information about A's percentage. The percentage bet's δ_A already reflects that bettor's view of A; the spread bet's δ_spread_direct also partly reflects it. Simply summing the signals may overcount. One mitigation: weight the indirect signal lower (e.g. 0.5×) to discount potential overlap.
- **Correlation.** The MC samples are already paired (A and B's finishes in each trial are correlated by the simulated match conditions). Shifting A's marginal distribution while holding B fixed may slightly distort the correlation structure. For small δ values this is negligible; for large shifts it may matter.
- **Place bets as inputs.** Place bets on A or B also carry information about their strength, which could in principle feed into spread calculations. The mapping is less direct (place → percentage requires the MC joint distribution), but the same framework could accommodate it by computing δ_place for each shooter and deriving the implied percentage shift from the shifted MC samples.

## Appendix: Unified Signal Propagation Across Market Types

### Motivation

Currently, each market type (place, percentage, spread) computes its δ independently from bets on that type. But all three types describe the same underlying reality: a shooter's performance in a match. A place bet on "A finishes 1st-10th" carries information about A's percentage finish, because finishing 20th instead of 26th *necessarily* means a better percentage than the model predicted for 26th place. The MC simulation already encodes these relationships — each trial has a finish position, a percentage, and (implicitly) a spread against every other shooter. The question is whether we can let evidence flow across types.

### The Core Idea: Shift in One Domain Implies a Shift in the Other

The MC trials are the bridge. Each trial for shooter A has both a finish position and a percentage:

```
Trial 1: finished 23rd, 78.2%
Trial 2: finished 31st, 71.5%
Trial 3: finished 18th, 82.1%
...
```

These are jointly sampled — a trial where A finishes 18th also has a specific percentage that's consistent with finishing 18th in that simulated field. When we compute a δ_place (shifting finish positions), the MC samples let us observe what that shift implies for percentage.

**Concrete example:** A's model expects ~26th. Place bets imply δ_place ≈ 6 positions (implied ~20th). We shift A's finish samples by 6. Now look at the percentage that goes with the shifted samples — the trials where the original finish was around 26th (now shifted to ~20th) had percentages around 74-76%. But the trials where the original finish was around 20th (now shifted to ~14th) had percentages around 80-82%. The shifted distribution's mean percentage is higher than the unshifted one. That implied percentage shift can be measured directly from the MC samples:

```
mean_pct_unshifted = mean of all pctA_i
mean_pct_shifted   = mean of pctA_i for trials where (finishA_i - δ_place) ≈ new expected finish

implied_δ_pct ≈ mean_pct_shifted - mean_pct_unshifted
```

More precisely, since each MC trial is a complete snapshot of the match, shifting the finish position and reading off the percentage that corresponds to the new position gives us the cross-domain mapping for free.

### A Rough Unified Flow

When generating odds for any market on shooter A:

1. **Gather all bets on A** across all types (place, percentage, spread involving A).
2. **Compute type-specific posteriors** — group bets by type, sum weights, compute posteriors within each type as before.
3. **Convert to a common signal.** Use the MC joint distribution to translate each type's evidence into a shift in a common underlying quantity. The natural common quantity is **percentage** (or equivalently, the shooter's latent strength), since:
   - Percentage bets give δ_pct directly.
   - Place bets give δ_place, which implies a δ_pct via the MC joint distribution (shift the finish samples, observe the corresponding percentage shift).
   - Spread bets give δ_spread for a pair, which implies a δ_pct for each shooter in the pair (though with some ambiguity about how to split the shift between A and B).
4. **Combine the converted signals** into a single δ_pct for the shooter, e.g. via weighted average of the implied δ_pct from each type, weighted by total bet weight behind each.
5. **Generate odds** for the requested market by applying the unified δ_pct (converted back to the target type's domain via the MC samples if needed).

### Why Percentage as the Common Signal

Percentage is the most natural common currency because:

- It's a continuous, per-shooter quantity (unlike place, which is relative to the field and discrete).
- It maps cleanly to strength — a better shooter has a higher expected percentage.
- Spread is literally a difference of two percentages, so `δ_spread = δ_pct_A - δ_pct_B` falls out naturally (as described in the previous appendix).
- Place can be derived from percentage given the field (a higher percentage implies a better place, with the mapping defined by the MC joint distribution of the full field).

Place could also work as the common signal, but the discreteness and field-dependence make it slightly less clean. The choice may depend on implementation convenience.

### Complexity and When It Matters

Unified propagation is most valuable when:

- A shooter has bets across multiple types (e.g. both place and percentage bets) — the evidence reinforces.
- Spread bets exist alongside individual percentage bets on the involved shooters — the spread appendix case.
- A shooter has many place bets but someone requests a percentage market (or vice versa).

It matters less when bets are sparse or concentrated in a single type, since there's nothing to propagate across.

### Open Questions

- **Mapping fidelity.** The place → percentage mapping via MC samples is approximate (the MC is a finite sample of the joint distribution). With 10,000 trials this is likely fine, but worth validating.
- **Split ambiguity for spreads.** A spread bet on "A beats B by ≥5%" could mean A is better than expected, B is worse, or both. Without additional evidence, the simplest assumption is to split the shift equally (each gets half the δ_spread), but if individual percentage bets exist for one or both shooters, those can anchor the split.
- **Computational cost.** Computing δ per type and then converting is cheap (MC sample lookups). The unified weighted average is O(1) on top of the per-type δ searches. So this adds negligible cost.
- **Double-counting (same concern as spread appendix).** If someone places both a place bet and a percentage bet on the same shooter, both signals carry related information. Weighting the unified signal needs care to avoid overcounting. A conservative approach: use the *maximum* rather than the sum of implied δ_pct from different types, or discount secondary types by a factor < 1.

---

*This document represents a comprehensive plan for Bayesian odds adjustment. Implementation should proceed incrementally with extensive testing at each stage.*
