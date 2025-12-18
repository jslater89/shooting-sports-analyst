/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "package:shooting_sports_analyst/data/help/entries/glicko2_help.dart";
import "package:shooting_sports_analyst/data/help/help_topic.dart";

const glicko2ConfigHelpId = "glicko2_config";
const glicko2ConfigHelpLink = "?glicko2_config";
final helpGlicko2Config = HelpTopic(
  id: glicko2ConfigHelpId,
  name: "Glicko2 configuration",
  content: _content,
);

const _content =
"""# Glicko-2 Configuration

The Glicko-2 rating system can be fine-tuned through several parameters. This guide explains each
setting and its effects. For general information on the Glicko-2 rating system, see the
[Glicko-2 help entry]($glicko2HelpLink).

Glicko-2 uses an internal representation of ratings where (with the default settings) the
1500-point starting rating corresponds to an internal rating of 0, according to the formula
(rating - initialRating) / scalingFactor. Starting RD, maximum RD, and maximum rating delta
are all specified with the same scaling. Use the 'apply' button next to calculated scaling
factor to set starting RD, maximum RD, and maximum rating delta to the default values,
scaled to the current initial rating.

### Initial Rating
The initial rating for new competitors. Controls the scaling factor.

### Scaling Factor
The conversion factor to go from display units for ratings and RDs to the internal
representation. Derived from the initial rating provided and the default initial rating
of 1500.

### Starting RD
The rating deviation for new competitors. Competitors with high ratings deviations will
have a smaller impact on the ratings of their opponents, and their ratings will change more
quickly.

### Maximum RD
The maximum value to allow for a competitor's rating deviation. Both temporal RD gain and
RD gain from commits following a match are capped at this value.

### Maximum Rating Delta
The maximum rating change to allow per match (both positive and negative). This falls into
the category of 'ugly hacks'; it prevents occasional extreme overperformances or
underperformances from breaking the system. The default value of 500 (with the default
scale factor) is relatively conservative. Observationally, 1000 or more means 'disabled'.

### Maximum New Opponent Count
The maximum number of opponents to consider when calculating rating updates for new players.
This helps prevent excessive rating changes for new competitors joining mature rating sets,
where comparing against many opponents with large rating gaps can cause rating changes to
accumulate to problematic values before Glicko-2's stabilizing features come into play at
the end of a match.

### Maximum Existing Opponent Count
The maximum number of opponents to consider when calculating rating updates for existing players.
This functions similarly to the above setting, but applies to existing players instead. Leave
empty (the default) for no limit: observationally, players who have appeared before will have
sufficient rating information to avoid the numerical instability solved by the above setting.

### Limit Opponents Mode
The method to use to select opponents if either maximum number of opponents above is exceeded.
Rating mode uses opponents closest in rating. Finish mode uses opponents closest in final match
result.

### Tau
The tau value controls the rate of volatility changes. Lower values of tau will make
volatility more resistant to change. There is no strict minimum, but amounts below 0.2-0.3
will essentially disable volatility changes. There is also no strict maximum, but amounts
higher than 1.2 will make volatility change too rapidly.

### Pseudo Rating Period Length
Standard Glicko-2 increases competitors' rating deviations once per rating period. Since
Analyst does not use calendrical rating periods, this value is used to calculate a fractional
number of pseudo rating periods since each competitor's last rating change for the purposes
of applying RD increases. The value is in days. On the ratings list, the current RD displayed
is the RD as of the current system clock time on the host machine.

### Initial Volatility
The initial volatility for new competitors. The default value of 0.06 is reasonable. Volatility
is capped at 0.15. Volatility is not affected by the scaling factor. On the ratings list, the
displayed volatility is scaled to show the RD increase per rating period for a competitor with
a very low RD (25 with the default scaling factor).

RD increases over time are faster for competitors with higher volatility and lower RD.

### Opponent Selection Mode
Glicko-2 is a head-to-head rating system, so it may be applied to a subset of eligible competitors
at a match. **All** uses all competitors at a match in the same division. **Top 10%** uses the top
10% of competitors at a match by both rating and match finish. (The lists are combined, and any
competitor appearing on either list will be used.) **Nearby opponents** uses competitors within either
a 10% match finish of the competitor being rated, or who have a rating within one starting RD of
the rating of the competitor being rated. **Top and nearby** uses the combination of top 10% and
nearby opponents.

### Score Function
The score between two competitors must be a number between 0 and 1. Score functions map competitor
finishes to internal scores. The all-or-nothing score function gives a score of 1.0 for a head-to-head
win and 0.0 for a head-to-head loss. (Or, in the very unlikely event of an exact tie, 0.5.) The
linear margin of victory score function accounts for margin of victory. A competitor who wins or loses
by more than the perfect victory difference (default 0.25) is given a score of 1.0 or 0.0, respectively.
A competitor who wins or loses by less than the perfect victory difference is given a score between 0.5
and 1.0 or 0.0 and 0.5, respectively.

### Perfect Victory Difference
The margin of victory or defeat that results in a perfect victory score (1.0) or perfect loss score (0.0),
when using the linear margin of victory score function.

### Linear Region
The size of the region where the expected score function is approximately linear, for the purposes of
calculating percentage predictions. The default value of 0.125 means that the linear region is between
0.125 and 1 - 0.125 = 0.875. Making this value smaller will allow for comparisons between more distant
competitors when calculating predictions, but will also tend to compress the outputs and produce too-high
predictions for the bottom of the field. Making this value larger will more closely match the behavior
of the linear margin of victory score function, but will also reduce the number of comparisons between
competitors and may reduce overall accuracy. The default value of 0.125 represents a reasonable compromise.

### Margin of Victory Inflation
A factor by which to inflate the expected margin of victory when calculating predictions. This can reduce
the impact of larger linear region settings by artificially reversing the compression effect of that
setting. By default it is set to 1, which means 'off'. A value of 1.05 means to inflate the expected margin
of victory by 5%.

### By Stage
Whether to calculate and update ratings by stage (checked) or by match (unchecked). By match is default
and recommended. By stage is still experimental and yields very volatile ratings. The following settings
are recommended:

* Maximum rating delta: 100 (with default scaling)
* Tau: 0.05
""";