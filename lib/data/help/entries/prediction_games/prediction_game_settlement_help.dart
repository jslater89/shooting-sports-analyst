/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "package:shooting_sports_analyst/data/help/help_topic.dart";

const predictionGameSettlementHelpId = "prediction-game-settlement";
const predictionGameSettlementHelpLink = "?$predictionGameSettlementHelpId";

final helpPredictionGameSettlement = HelpTopic(
  id: predictionGameSettlementHelpId,
  name: "Settlement",
  content: _content,
);

const _content =
"""# Settlement

After a match completes and scores are available, open the settlement dialog from the match list
on the game manager (linked-dataset icon). The dialog lists all wagers for that match with live
score evaluation.

## Main Result vs Prediction Set Result

For each open wager, the UI shows whether legs hit against:

* **Main result** — full match scores within the wager's scoring group.
* **Prediction set result** — scores restricted to the competitors who were in the prediction set
  roster (the field that was predicted against).

These can differ when squadding or registration changes between prediction time and match day.
Two resolve buttons let you settle against either basis. Choose the one that matches your
contest rules.

Score columns for spread wagers show the realized spread on both main and prediction-set bases.

## Resolving Wagers

For each wager:

* Pay (filled icon) — mark won and credit payout to the player's balance.
* Close (outline icon) — mark lost; stake stays with the house.
* Void (clear icon) — refund the stake (and reclaim any erroneous payout). Use when registration
  changed enough to invalidate the wager.

Resolved wagers dim in player wager lists. Voided wagers are excluded from accuracy statistics.""";
