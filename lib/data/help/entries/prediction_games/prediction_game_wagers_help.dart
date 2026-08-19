/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "package:shooting_sports_analyst/data/help/entries/latent_log_help.dart";
import "package:shooting_sports_analyst/data/help/help_topic.dart";

const predictionGameWagersHelpId = "prediction-game-wagers";
const predictionGameWagersHelpLink = "?$predictionGameWagersHelpId";

final helpPredictionGameWagers = HelpTopic(
  id: predictionGameWagersHelpId,
  name: "Wagers and odds",
  content: _content,
);

const _content =
"""# Wagers and Odds

From a player's screen, select a match and rating group, then click Wager. The wager dialog lists
eligible competitors from the match prep's latest prediction set, sorted by rating.

## Wager Types

* **Place** — the competitor finishes between a best and worst place (inclusive). A single place
  uses the same value for both bounds. A better-than-place wager should use best place 1, worst
  place N, while a worse-than-place wager should use best place N, worst place some large number.
  (It need not be the total number of competitors as long as it's larger than that.)
* **Percentage** — the competitor finishes above or below a percentage threshold relative to
  the winner.
* **Spread** — the favorite must cover (or the underdog must beat) a percentage spread against
  another named competitor.

Add up to ten legs. With one leg, save as an independent wager. With multiple legs, save as a
**parlay**: all legs must hit for the wager to win. Parlay odds combine leg probabilities with
an additional house edge on top of the per-leg edge.

Odds display as moneyline values. Payout uses standard moneyline rounding.

## Eligibility

The game can restrict which competitors appear in the wager dialog:

* **Minimum competitors** — the rating group at the match must have at least this many
  registered competitors with predictions (default 10).
* **Minimum projected finish ratio** — competitors whose predicted finish percentage center falls
  below the threshold are ineligible.
* **Minimum stage or match history** — competitors with too little rating history are ineligible.
* **Maximum rating age** — competitors not seen within the given number of days are ineligible.
* **Excluded rating groups** — groups listed in the game configuration never offer wagers (for
  example combined LO/CO groups). Prediction sets may also exclude groups independently.

Ineligible competitors show a short reason in the wager dialog.

## Odds and Bayesian Adjustment

Base odds come from Monte Carlo simulation over the rating algorithm's predictions for each
competitor (12,500 trials by default). The simulation respects the selected scoring group and
prediction set roster.

When a player requests odds, the system applies **Bayesian odds adjustment**: prior wagers on
the same competitor and market type are treated as evidence that shifts the model distribution
before the requested line is priced. Key behaviors:

* Each accepted wager contributes weight based on bet size relative to the bettor's bankroll
  (conviction), time until the match (early bets count less), and the bettor's historical
  sharpness (win rate relative to implied probability).
* Similar wagers on nearby place ranges or percentage thresholds contribute additional effective
  weight, so a bet on "1st-5th" also moves the line on "1st-3rd" appropriately.
* Spread wagers decompose into percentage signals for each involved shooter.
* Shooter rating history length controls how strongly the model resists movement: deep histories
  yield tighter priors; newcomers' lines move more with early action.
* A standard **house edge** of 5% is applied to single wagers; parlays carry an additional edge.

Supported rating algorithms for Bayesian adjustment are Elo, Glicko-2, and Latent Log-Ratio.
The [Latent Log-Ratio]($latentLogHelpLink) system was tuned with the Prediction Game in mind
and generally produces the sharpest pre-match lines.""";
