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

## Market Similarity and Cross-Market Adjustment

### The Problem

Player bets on "Max Michel 1st-3rd" but there's also a market for "Max Michel 1st-5th". These are related: if money suggests Max is more likely to finish 1st-3rd, he's probably also more likely to finish 1st-5th. We need to propagate wager signals across related markets without requiring exact market matching.

### Cross-Market Update Algorithm

For every wager we process, the flow is:

1. **Calculate raw odds from the prediction engine (Monte Carlo).**
   This gives the model prior (α, β from N_eff and P) and baseline odds before wager-based adjustment.

2. **Find related markets.**
   Minimally: markets that share the same subject (same shooter for place/percentage; same shooter pair for spread). Optionally restrict to same prediction type. No need for a continuous "similarity score" to link markets—same subject is sufficient.

3. **Determine direction.**
   For each related market, decide whether the wager adds to **alpha** (pulls P up) or **beta** (pulls P down). Overlap matters for place (overlapping ranges → same direction → add to alpha; disjoint e.g. 1st-3rd vs 10th-20th → opposite → add to beta). Range size can play a role. For percentage: same side of the line (above vs below) gives direction. For spread: which side. So we use overlap and outcome consistency to choose alpha vs beta, not to scale strength.

4. **Set effect strength from relative odds (plus player adjustments).**
   The odds at which the bet was placed—not a structural similarity score—drive how strongly we update. A bet on a long shot (e.g. +4000 for "A 1st-3rd") is a strong conviction signal: existing long shots that get action should pull probability in the direction of "this long shot is more likely." So strength = (bet weight from conviction × skill × time) × f(odds), where f(odds) reflects the longness of the odds (e.g. decimal odds or 1/implied P). The same subject links the markets; the odds (and player weight) determine the size of the update.

**Summary:** Link = same subject. Direction = overlap / outcome consistency (alpha vs beta). Strength = relative odds + player adjustments. Exact structural similarity (Jaccard, percentage distance) is not required.

### Link: Same Subject

We do **not** need a continuous similarity function to decide *whether* to propagate. Same subject is sufficient:

- **Place or percentage on one shooter:** same shooter (e.g. same `memberNumber`) links all that shooter's markets.
- **Spread:** same two shooters (target + underdog) link spread markets.

Example: a wager on "A 1st-3rd" at +4000 and a market "A 10th-20th" at +110 are linked because both are about shooter A. We then use direction (opposite: disjoint place ranges) and odds (the +4000 bet is a strong signal) to update the 10th-20th market (add to beta there).

### Direction

For each related market we must choose: add to **alpha** (increase P) or **beta** (decrease P).

- **Place:** Overlap and range matter. Overlapping place ranges (e.g. 1st-3rd and 1st-5th) → same direction → add to alpha on the other market. Disjoint ranges (e.g. 1st-3rd vs 10th-20th) → opposite → add to beta on the other market. Range size can refine (e.g. narrow vs wide).
- **Percentage:** Same direction (both "above X%" or both "below X%") → add to alpha. Opposite (above vs below) → add to beta.
- **Spread:** Same side (favorite covers vs underdog covers) → add to alpha; opposite side → add to beta.

So overlap (and type) is used for **direction only**, not as the multiplier for effect strength.

### Effect Strength: Relative Odds

Signal strength comes from **odds** (and player weight), not from a structural similarity score:

- Long odds on the bet (+4000) = strong conviction that this outcome is more likely than the line implies → large update (in the chosen direction) to related markets.
- The relative odds between the bet market and the target market can also scale the update (e.g. how much probability mass is shared or how complementary the outcomes are).

So: "Existing long shots [that get action] should tend to pull the probability in the direction of 'this long shot is more likely.'" The longness of the odds is what makes that pull strong.

### Cross-Market Update (Procedure)

When a bet is placed:

1. Compute bet weight (conviction × skill × time decay × base weight).
2. Find all markets with the same subject (and optionally same type).
3. For each related market: compute direction (add to alpha vs beta) from overlap/outcome consistency.
4. For each: compute effect strength from odds (e.g. f(decimal odds or implied P)) and apply `accumulatedAlpha += strength` or `accumulatedBeta += strength` accordingly.

```dart
void updateAcrossMarkets({
  required DbPrediction betMarket,
  required List<MarketState> allMarkets,
  required double betWeight,
  required double betImpliedP,
  // Optional: odds-based strength multiplier (long odds => stronger)
  double oddsStrengthMultiplier(double impliedP) => 1.0 / impliedP.clamp(0.01, 1.0),
}) {
  for (var market in allMarkets) {
    if (!sameSubject(betMarket, market.prediction)) continue;

    bool addToAlpha = sameDirection(betMarket, market.prediction);
    double strength = betWeight * oddsStrengthMultiplier(betImpliedP);

    if (addToAlpha) {
      market.accumulatedAlpha += strength;
    } else {
      market.accumulatedBeta += strength;
    }
  }
}
```

**Example:** Wager on "A 1st-3rd" at +4000 (implied P ≈ 2.4%), weight = 2.0, odds multiplier 1/0.024 ≈ 41.7 → strength ≈ 83.4. All markets for shooter A are updated: same-direction (e.g. "A 1st-5th") get alpha += 83.4; opposite-direction (e.g. "A 10th-20th") get beta += 83.4. No similarity threshold; same subject is the link.

### Direction and Overlap (Reference)

The following helpers can be used to implement **direction** (same vs opposite) for place, percentage, and spread. They are not used as effect-strength multipliers; odds drive strength.

```dart
double calculateSimilarity(DbPrediction market1, DbPrediction market2) {
  if (market1.target.memberNumber != market2.target.memberNumber) {
    return 0.1;  // no link (or small for cross-shooter sentiment)
  }

  if (market1.type == market2.type) {
    switch (market1.type) {
      case DbPredictionType.place:
        return _placeSimilarity(market1, market2);

      case DbPredictionType.percentage:
        return _percentageSimilarity(market1, market2);

      case DbPredictionType.spread:
        return _spreadSimilarity(market1, market2);
    }
  }

  return 0.3;  // same shooter, different prediction types
}

// Use overlap to determine same vs opposite direction for place (0 = disjoint → opposite)
double _placeSimilarity(DbPrediction m1, DbPrediction m2) {
  if (m1.bestPlace == m2.bestPlace && m1.worstPlace == m2.worstPlace) {
    return 1.0;
  }

  int overlapStart = max(m1.bestPlace!, m2.bestPlace!);
  int overlapEnd = min(m1.worstPlace!, m2.worstPlace!);
  int overlapSize = max(0, overlapEnd - overlapStart + 1);

  int m1Size = m1.worstPlace! - m1.bestPlace! + 1;
  int m2Size = m2.worstPlace! - m2.bestPlace! + 1;

  int unionSize = m1Size + m2Size - overlapSize;
  return overlapSize / unionSize;  // Jaccard: 0 = disjoint (opposite), 1 = same
}

double _percentageSimilarity(DbPrediction m1, DbPrediction m2) {
  if (m1.abovePercentage != m2.abovePercentage) return 0.3;  // opposite direction

  double diff = (m1.percentage! - m2.percentage!).abs();
  return exp(-20 * diff);
}

double _spreadSimilarity(DbPrediction m1, DbPrediction m2) {
  if (m1.target.memberNumber != m2.target.memberNumber) return 0.1;
  if (m1.underdog?.memberNumber != m2.underdog?.memberNumber) return 0.1;
  if (m1.favoriteCovers != m2.favoriteCovers) return 0.3;  // opposite direction

  double diff = (m1.percentage! - m2.percentage!).abs();
  return exp(-15 * diff);
}
```

Use overlap (e.g. Jaccard == 0 for place → opposite) and above/below or favorite/underdog to set `sameDirection`; do not use these scores as the effect-strength multiplier.

## Risk Management

### Maximum Odds Movement

Protect against over-adjustment:

```dart
double getAdjustedProbability({
  required double modelAlpha,
  required double modelBeta,
  required double accumulatedAlpha,
  required double accumulatedBeta,
  double maxMovementFraction = 0.20,
}) {
  double modelProb = modelAlpha / (modelAlpha + modelBeta);
  double rawNewProb = (modelAlpha + accumulatedAlpha) /
                      (modelAlpha + modelBeta + accumulatedAlpha + accumulatedBeta);

  // Limit movement to ±20% of model probability
  double maxMove = modelProb * maxMovementFraction;
  return rawNewProb.clamp(modelProb - maxMove, modelProb + maxMove);
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

Reset accumulated evidence as match approaches:

**Option A**: Full reset at match start
```dart
// At match start, reset accumulated evidence
accumulatedAlpha = 0.0;
accumulatedBeta = 0.0;
```

**Option B**: Gradual decay
```dart
// Each day, decay accumulated evidence by 5%
accumulatedAlpha *= 0.95;
accumulatedBeta *= 0.95;
```

**Recommendation**: Use Option A for simplicity.

## Implementation Considerations

### Data Storage

Add to `DbWager` or create new `MarketState` class:

```dart
@embedded
class MarketBayesianState {
  // Model's base confidence
  double modelAlpha;
  double modelBeta;

  // Accumulated evidence from bets
  double accumulatedAlpha = 0.0;
  double accumulatedBeta = 0.0;

  // Metadata
  DateTime lastUpdated;
  int totalBetsProcessed = 0;
}
```

### Recalculation Triggers

Recalculate odds when:
1. New bet is placed (immediate update)
2. Bet is voided/removed (reverse the update)
3. Player's accuracy changes significantly (retroactive adjustment?)
4. Time-based: daily recalculation as match approaches

### Bet Removal/Voiding

If a bet is voided, reverse its impact:

```dart
void reverseBet({
  required MarketState market,
  required double betWeight,
}) {
  market.accumulatedAlpha -= betWeight;
  market.accumulatedAlpha = max(0, market.accumulatedAlpha);  // floor at 0
}
```

### Performance Optimization

For large numbers of markets:
1. **Index by subject**: Group markets by shooter (or shooter pair for spreads) for faster same-subject lookups
2. **Lazy evaluation**: Only recalculate odds when they're viewed/needed
3. **Batch updates**: Process multiple bets before recalculating all affected markets
4. **Cache direction**: Optionally cache same/opposite direction per market pair if direction checks are expensive

## Tunable Parameters Summary

| Parameter | Recommended | Conservative | Aggressive | Description |
|-----------|-------------|--------------|------------|-------------|
| **Model Confidence** (α + β) | 50-100 | 100-200 | 25-50 | Higher = less movement from bets. Prefer setting via N_eff from rating history (see "Principled Setting of α and β"). |
| **Base Weight** | 10.0 | 5.0 | 20.0 | Overall bet impact scaling |
| **Time Decay λ** | 0.10 | 0.05 | 0.15 | Rate of early bet discounting |
| **Odds strength multiplier** | 1/implied P | — | — | Long odds ⇒ stronger cross-market update. Link is same subject; no similarity threshold. |
| **Max Movement** | 20% | 10% | 30% | Maximum probability shift from model |
| **Min Bets for Skill** | 10 | 20 | 5 | Minimum resolved bets to apply skill multiplier |

## Testing Strategy

### Unit Tests

1. **Basic updates**: Single bet moves probability correctly
2. **Weight calculation**: All factors (conviction, skill, time) combine properly
3. **Direction and same-subject**: Same-subject markets updated; direction (alpha vs beta) correct for overlapping vs disjoint outcomes
4. **Bounds checking**: Probabilities stay in [0, 1], max movement enforced
5. **Reversibility**: Voiding a bet returns to previous state

### Integration Tests

1. **Multiple bets**: Sequential bets accumulate correctly
2. **Cross-market**: Bet on one market affects same-subject markets; direction and strength from odds
3. **Player learning**: As player's accuracy changes, future bets weighted differently
4. **Time progression**: Old bets decay as match approaches

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

### Complete Update Function

```dart
class BayesianOddsManager {
  // Per-market state
  Map<String, MarketBayesianState> marketStates = {};

  void processBet({
    required DbWager wager,
    required PredictionGamePlayer player,
    required MatchPrep matchPrep,
    required double baseWeight,
    required double lambda,
    required double betImpliedP,
  }) {
    // Calculate bet weight (conviction × skill × time)
    double weight = calculateBetWeight(
      wager: wager,
      player: player,
      matchDate: matchPrep.matchDate,
      baseWeight: baseWeight,
      lambda: lambda,
    );

    // Odds-based strength: long odds => stronger cross-market signal
    double strength = weight * (1.0 / betImpliedP.clamp(0.01, 1.0));

    // Update primary market
    String marketKey = _getMarketKey(wager.legs.first);
    MarketBayesianState state = _getOrCreateState(marketKey, wager);
    state.accumulatedAlpha += weight;
    state.totalBetsProcessed++;
    state.lastUpdated = DateTime.now();

    // Update same-subject markets (direction from overlap/outcome consistency)
    var betPrediction = _getMarketPrediction(marketKey);
    for (var entry in marketStates.entries) {
      if (entry.key == marketKey) continue;

      var otherPrediction = _getMarketPrediction(entry.key);
      if (!sameSubject(betPrediction, otherPrediction)) continue;

      bool addToAlpha = sameDirection(betPrediction, otherPrediction);
      if (addToAlpha) {
        entry.value.accumulatedAlpha += strength;
      } else {
        entry.value.accumulatedBeta += strength;
      }
    }
  }

  PredictionProbability getAdjustedProbability(
    String marketKey,
    PredictionProbability modelProbability,
    {double maxMovementFraction = 0.20}
  ) {
    MarketBayesianState? state = marketStates[marketKey];
    if (state == null) {
      return modelProbability;  // no adjustments yet
    }

    double totalAlpha = state.modelAlpha + state.accumulatedAlpha;
    double totalBeta = state.modelBeta + state.accumulatedBeta;
    double adjustedProb = totalAlpha / (totalAlpha + totalBeta);

    // Apply max movement limit
    double modelProb = state.modelAlpha / (state.modelAlpha + state.modelBeta);
    double maxMove = modelProb * maxMovementFraction;
    adjustedProb = adjustedProb.clamp(
      modelProb - maxMove,
      modelProb + maxMove,
    );

    return PredictionProbability(
      adjustedProb,
      houseEdge: modelProbability.houseEdge,
      worstPossibleOdds: modelProbability.worstPossibleOdds,
      bestPossibleOdds: modelProbability.bestPossibleOdds,
    );
  }

  // Helper methods
  String _getMarketKey(DbPrediction prediction) {
    // Create unique key for market
    return "${prediction.target.memberNumber}_${prediction.type}_${prediction.bestPlace}_${prediction.worstPlace}_${prediction.percentage}";
  }

  MarketBayesianState _getOrCreateState(String key, DbWager wager) {
    return marketStates.putIfAbsent(key, () {
      var prob = wager.wagerProbability;
      return MarketBayesianState(
        modelAlpha: 65.0,  // TODO: set from N_eff and model P (see "Principled Setting of α and β"), e.g. P*nEff, (1-P)*nEff using shooter rating history
        modelBeta: 35.0,
        lastUpdated: DateTime.now(),
      );
    });
  }

  DbPrediction _getMarketPrediction(String key) {
    // TODO: Parse key back to prediction
    throw UnimplementedError();
  }
}
```

---

*This document represents a comprehensive plan for Bayesian odds adjustment. Implementation should proceed incrementally with extensive testing at each stage.*
