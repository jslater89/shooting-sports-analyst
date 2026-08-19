/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "package:shooting_sports_analyst/data/help/entries/configure_ratings_help.dart";
import "package:shooting_sports_analyst/data/help/entries/match_preps/match_preps_help.dart";
import "package:shooting_sports_analyst/data/help/entries/prediction_games/prediction_game_manager_help.dart";
import "package:shooting_sports_analyst/data/help/entries/prediction_games/prediction_game_players_help.dart";
import "package:shooting_sports_analyst/data/help/entries/prediction_games/prediction_game_settlement_help.dart";
import "package:shooting_sports_analyst/data/help/entries/prediction_games/prediction_game_wagers_help.dart";
import "package:shooting_sports_analyst/data/help/entries/ratings/ratings_view_help.dart";
import "package:shooting_sports_analyst/data/help/help_topic.dart";

const predictionGamesHelpId = "prediction-games";
const predictionGamesHelpLink = "?$predictionGamesHelpId";

final helpPredictionGames = HelpTopic(
  id: predictionGamesHelpId,
  name: "Prediction games",
  content: _content,
);

const _content =
"""# Prediction Games

The canonical Prediction Game runs on the Shooting Sports Analyst website, but the desktop app
includes a largely equivalent local experience for running prediction contests against your own
match data. A prediction game is a season-long contest in play money: players wager on upcoming
match outcomes using odds derived from your [rating projects]($configureRatingsHelpLink), settle
wagers when results arrive, and compete on a leaderboard.

Prediction games depend on [match preps]($matchPrepsHelpLink): pre-match prediction sets attached
to upcoming matches. Create and maintain match preps from the [ratings view]($ratingsViewHelpLink)
(crystal-ball icon), the home-page match prep list, or from within a game. A match prep must have
at least one prediction set with algorithm predictions before wagers can be offered on that match.

## Getting Started

Open Prediction Games from the home page. The plus icon creates a new game. You supply a name,
optional description, minimum competitors per rating group (default 10), and optional start and
end dates that gate when the game is considered active.

Click a game to open the manager view. Three areas organize day-to-day work:

* **House stats** at the top summarize open and closed wager volume, house profit or loss, and
  total player bankroll. See [Game manager]($predictionGameManagerHelpLink).
* **Players** on the left lists participants, their balances, and links to each player's wager
  screen. See [Players]($predictionGamePlayersHelpLink).
* **Matches** on the right lists attached match preps, total action per match, and settlement
  tools. See [Game manager]($predictionGameManagerHelpLink) and [Settlement]($predictionGameSettlementHelpLink).

Use ADD PLAYER to enroll participants with a starting balance (default 50). Use ADD MATCH to
attach an existing match prep from any rating project in your database.

## Placing and Settling Wagers

Players place bets from their individual screens. See [Wagers and odds]($predictionGameWagersHelpLink)
for wager types, eligibility, and how lines are priced. After a match completes, settle wagers from
the match list. See [Settlement]($predictionGameSettlementHelpLink).

## Configuration Notes

Most advanced game settings (eligibility thresholds, excluded groups, disabled match preps) are
stored on the game record and can be adjusted through database tools even when not yet exposed in
the creation dialog. The creation dialog sets name, description, minimum competitors, and optional
start and end dates only.

Start and end dates control whether the game is considered active for future online features;
local wager placement is gated primarily by whether the match date is still in the future.

## Tips

Build match preps early, while registration is stable but before the match. Lines are most
interesting when several players have already wagered and Bayesian adjustment has had time to
incorporate the action.

Prefer prediction sets whose roster matches who will actually shoot. Settlement against the
prediction set result is designed for cases where the predicted field differs from the final
match result.

For parlays, remember that each leg carries house edge and the parlay itself adds another edge;
long parlays are long shots by design.

If balances look wrong after manual edits or interrupted saves, run Audit on affected players
before settling more wagers.""";
