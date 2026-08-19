/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "package:shooting_sports_analyst/data/help/entries/prediction_games/prediction_game_players_help.dart";
import "package:shooting_sports_analyst/data/help/entries/prediction_games/prediction_game_settlement_help.dart";
import "package:shooting_sports_analyst/data/help/help_topic.dart";

const predictionGameManagerHelpId = "prediction-game-manager";
const predictionGameManagerHelpLink = "?$predictionGameManagerHelpId";

final helpPredictionGameManager = HelpTopic(
  id: predictionGameManagerHelpId,
  name: "Game manager",
  content: _content,
);

const _content =
"""# Game Manager

The game manager is the main screen after you open a prediction game from the list. House stats
span the top; players and matches share the space below in two columns.

## House Statistics

The header summarizes the house position across all wagers in the game:

* Open wager volume and house risk (total payout if every open bet wins).
* Closed wager volume, player winnings, and house net profit (excluding voids).
* Voided stake (net zero to the house).
* Sum of all player balances.

Per-player wagered, won, and accuracy figures appear on the [player screen]($predictionGamePlayersHelpLink).

## Players Column

The left column lists enrolled players with nickname and balance. Use ADD PLAYER to create a
participant with a starting balance (default 50). Tap a row to open that player's wager screen.
The delete icon removes a player from the game.

Player management details — top-ups, audit, editing, and the wager/transaction lists — are covered
in [Players]($predictionGamePlayersHelpLink).

## Matches Column

The right column lists match preps attached to this game. Each row shows event name, rating
project, and total wager action on that match. Use ADD MATCH to attach an existing match prep
from any rating project in your database.

Tap a row to open the match prep itself. Trailing icons provide match-level actions:

* The scoreboard icon opens match results once scores exist.
* The linked-dataset icon opens the [wager settlement dialog]($predictionGameSettlementHelpLink)
  for that match.
* The delete icon removes the match from the game and deletes all associated wagers and
  transactions.

Each attached match prep connects one upcoming match to one rating project. Removing a match prep
from a game is destructive. Deleting the underlying match prep elsewhere in the app is a separate
operation and is blocked while a prediction game still references it.""";
