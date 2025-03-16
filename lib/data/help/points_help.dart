/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "package:shooting_sports_analyst/data/help/rating_event_help.dart";
import "package:shooting_sports_analyst/ui/widget/dialog/help/help_topic.dart";

const pointsHelpId = "points";
const pointsHelpLink = "?points";
final helpPoints = HelpTopic(
  id: pointsHelpId,
  name: "Points rating system",
  content: _content,
);

const _content = """# Points Rating System

The points rating system assigns points to shooters based on their match performance, with several different scoring
models available. Unlike Elo or OpenSkill, Points is a pure accumulation system - shooters never lose points, they only
gain them. The system can be configured to count only a shooter's best N matches, preventing the need to attend every
match to stay competitive.

## Scoring Models

Scoring models are the different ways that the points rating system assigns points to competitors based on match
performance. The points rater always operates in [by-match mode]($ratingEventHelpLink), and filters competitors based on
its active rating groups when calculating match scores.

The F1-style model awards points to the top 10 finishers in each match using the Formula 1 scoring system: 25 points for
first place, 18 for second, then 15, 12, 10, 8, 6, 4, 2, and 1 point for tenth place. This creates clear separation
between top performers while still rewarding consistent mid-pack finishes.

The Inverse Place model awards points based on how many competitors a shooter beats. In a match with 20 shooters, first
place earns 19 points (beating everyone except themselves), second place earns 18 points, and so on. This system scales
naturally with match size and rewards consistent attendance at larger matches.

The Percentage Finish model awards points equal to each shooter's match percentage. A shooter scoring 95% of the winner's
points would earn 95 points. This is a commonly-used system in cases like IPSC World Shoot qualification or, on the
other end of the spectrum, a club points series.

The Decaying Points model uses an exponential decay function, starting with a configurable number of points for first
place and multiplying by a decay factor for each subsequent place. For example, with a start of 30 points and a 0.8
decay factor, places would earn 30, 24, 19.2, 15.4, etc. This allows for custom-tuned separation between places.

## Configuration

The Matches to Count setting determines how many matches contribute to a shooter's total points. If set to 6, only their
6 highest-scoring matches (according to the selected scoring model) will count for their final score.

The Participation Bonus setting adds a fixed number of points for each match attended, regardless of performance. This
rewards match attendance and progression even when not placing highly. The bonus is added for all matches, not just the
_n_-best ones according to the Matches to Count setting.

For the Decaying Points model, **Decay start** sets the points awarded for first place, while the **Decay factor**
(between 0 and 1) is the multiplier applied at each step. For instance, with the default decay start of 30 and decay
factor of 0.8, the first three places would earn 30, 24 (= 30 × 0.8), and 19.2 (= 24 × 0.8) points.""";
