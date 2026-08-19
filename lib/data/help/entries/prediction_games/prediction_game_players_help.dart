/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "package:shooting_sports_analyst/data/help/entries/prediction_games/prediction_game_wagers_help.dart";
import "package:shooting_sports_analyst/data/help/help_topic.dart";

const predictionGamePlayersHelpId = "prediction-game-players";
const predictionGamePlayersHelpLink = "?$predictionGamePlayersHelpId";

final helpPredictionGamePlayers = HelpTopic(
  id: predictionGamePlayersHelpId,
  name: "Players",
  content: _content,
);

const _content =
"""# Players

Tap a player on the game manager's Players column to open their wager screen. The title shows
the game name and player nickname.

## Controls

The top bar shows balance and four actions:

* **Top up** — set balance to a target amount, or add a fixed amount.
* **Audit** — recompute balance from transactions and correct discrepancies.
* **Edit** — change nickname or top-up target balance.
* **Wager** — place new bets on a future match (see [Wagers and odds]($predictionGameWagersHelpLink)).

Below the controls, player stats show total wagered, total won, and hit rate on closed (non-voided)
wagers.

Select a match and rating group, then click Wager. Wagers require a future match date; once the
match has begun, the Wager button is disabled.

## Open Wagers and Transactions

The lower half splits into two lists:

* **Open Wagers** on the left shows the player's bets. Use **Show all wagers** to include closed
  and voided wagers. Resolved wagers dim in the list; voided wagers are excluded from accuracy
  statistics.
* **Transactions** on the right is the balance ledger for this player.

Every balance change is recorded:

* **Top-up** — manual or initial bankroll credit.
* **Wager** — stake debit when a bet is placed.
* **Payout** — credit when a wager wins.
* **Refund** — credit when a wager is voided.

The Audit button recomputes balance from this ledger. If balances look wrong after manual edits
or interrupted saves, run Audit before settling more wagers.""";
