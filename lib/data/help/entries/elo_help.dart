/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "package:shooting_sports_analyst/data/help/entries/elo_configuration_help.dart";
import "package:shooting_sports_analyst/data/help/help_topic.dart";

const eloHelpId = "elo";
const eloHelpLink = "?elo";
final helpElo = HelpTopic(
  id: eloHelpId,
  name: "Elo rating system",
  content: _content,
);

const _content =
"""# Elo Rating System

The Elo rating system, [originally developed for chess](https://en.wikipedia.org/wiki/Elo_rating_system), predicts match
outcomes by comparing the ratings of competitors. When actual results differ from predictions, ratings are adjusted
accordingly. For help configuring Shooting Sports Analyst's Elo implementation, see the [Elo configuration
guide]($eloConfigHelpLink).

## Core Concepts

* Higher ratings indicate stronger competitors
* Beating a higher-rated opponent gains more points than beating a lower-rated one
* The size of rating changes depends on how unexpected the result was

## Shooting Sports Adaptations

The system includes several modifications for shooting sports:

### Initial Ratings by Classification
In shooting sports where members commonly enter classifications during match registration, initial ratings are based on
classification. In USPSA, the figures are as follows:
* D=800
* C or U=900
* B=1000
* A=1100
* M=1200
* GM=1300

### Multiplayer Support
Whereas classical Elo compares competitors head-to-head, Shooting Sports Analyst's Elo is a [multiplayer
generalization](https://medium.com/towards-data-science/developing-a-generalized-elo-rating-system-for-multiplayer-games-b9b495e87802).
This allows the system to compare each competitor against the entire field holistically, rather than in pairwise fashion
against each other competitor.

### Confidence Adjustments
The system employs several confidence-based adjustments to improve accuracy. New shooters experience larger rating changes
initially to help establish their proper skill level quickly. The system includes error tracking that reduces rating
changes when predictions have been consistently accurate. Additionally, competitors who face a diverse range of opponents
receive more weight in their rating adjustments through connectivity tracking. The system also incorporates streak
detection to better respond to shooters who are rapidly improving or declining in performance.

### Stage-Specific
Stage characteristics influence rating adjustments in several ways. Shorter stages have a slightly reduced impact while
longer stages carry more weight in calculations. When many shooters score zero on a stage, its impact on ratings is
reduced. The system can also combine both stage and match results to balance between responsive rating changes and rating
stability based on match results.

### DNFs and Other Partial Results
Competitors who do not finish a match, or who disqualify at a match, are still rated on the stages that they completed.
Since a DNF or disqualification prevents a competitor from receiving a match score, match score blending is disabled
when rating DNFed or DQed competitors.

## Tips

When interpreting ratings, keep in mind that they cannot be directly compared across different divisions. Rating
differences of 50-100 points should be considered relatively minor. The algorithm performs best when analyzing groups of
competitors who frequently compete against each other. Isolated groups of competitors may have ratings that are less
reliable.""";
