/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */


import 'package:shooting_sports_analyst/data/help/help_topic.dart';

const matchHeatHelpId = "match_heat";
const matchHeatHelpLink = "?match_heat";

final helpMatchHeat = HelpTopic(
  id: matchHeatHelpId,
  name: "Match heat",
  content: _content,
);

const _content =
"""# Match Heat

The match heat screen shows a summary of the heat, or level of competition, at the matches
in the current rating project, using four different metrics. Heat is calculated for each
division at the match, and an average weighted by the proportion of competitors in each division
is used for the final, displayed values.

This screen is currently an early beta, and is only tested with the Elo rating algorithm and
USPSA matches. Other rating algorithms and sports _may_ provide reasonable outputs, but are
not yet guaranteed to work, or provide interesting results.

Any division with fewer than five rated competitors is excluded from the heat calculation.

Hovering over a match dot will show a summary of its heat along various axes. Clicking on a match
dot will show the scores for that match.

Match heat will be calculated for all matches in the project the first time the screen is opened,
and results for each match will be saved to the database. Subsequent visits to the screen will
add new matches to the database. The 'refresh' button in the top right of the screen will remove
all cached results from the database and recalculate heat for all matches.

## Measurements

### Match Size

The X axis shows the number of competitors at the match. All registered competitors with a rating
following the match will be included in the match size, even those that did not finish the match.
If the number of registered competitors differs from the number of competitors used to calculate
heat, the number of registered competitors will be shown first, and the number of competitors used
to calculate heat will be shown in parentheses.

### Top Ten Percent Average Rating

The Y axis shows the average rating of the best competitors at the match. This is calculated by
taking the top ten percent of competitors by finish position and averaging their ratings. If there
are fewer than 30 competitors in a match, the top 3 are used instead.

The competitor's rating at the time of the match is used for the calculation, unless the rating has
fewer than 50 stages on record. In that case, the most recent rating is used.

### Median Rating

The size of each match's dot shows the median rating of the competitors at the match. A median rating
of 800 Elo is displayed as a dot with a radius of 2 pixels. Each additional 40 Elo increases the radius
of the dot by 1 pixel.

The rating used is determined in the same manner as the Y-axis value.

### Average Classification Strength

The color of each match's dot shows the average classification strength of the competitors at
the match, relative to all matches in the project. The classification strength averages the
classification strengths of the relevant competitors, using values determined by each supported sport.

On each match's tooltip, classification is displayed in the format "A+24%", which indicates that the
average classification strength at the match is 24% of the way from A to the next higher classification.

## Display Options

The display options dialog, accessible from the action icon in the top right corner, allows
adjusting the display of the match heat graph.

### X and Y Axes

The X and Y axes autoscale to appropriate ranges for the selected data. Average classification uses
a synthetic value determined by the classification strengths defined by each sport. For USPSA,
classification strengths are as follows:

* GM: 10
* M: 6
* A: 4
* B: 3
* C: 2
* D: 1
* U: 2

Other sports may use different values, or may not use classification strengths at all.

### Dot Size

Each measurement defines its own scale for dot size.

* **Match Size**: 1 pixel radius for matches of fewer than 50 competitors, plus 1 pixel for each additional 50 competitors.
* **Top Ten Percent Average Rating**: 1 pixel radius for ratings less than 1200, plus 1 pixel for each additional 50 Elo.
* **Median Rating**: 1 pixel radius for ratings less than 800, plus 1 pixel for each additional 40 Elo.
* **Average Classification Strength**: 1 pixel radius for classification strengths in the bottom 10% of the range, up to
  10 pixels for the strongest classification strength in the data.

### Dot Color

Each measurement linearly interpolates between colors based on the position of the value within the range of the measurement.
Pure blue is the lowest value, and pure red is the highest value.

## Searching

The filter button at the top of the screen can be used to select matches to highlight on the graph.
Highlighted matches will be displayed in normal colors, while unhighlighted matches will be shown
in muted colors, and will no longer display tooltips.

A tooltip on the "N results" text at the top of the screen will show the average heat of the
highlighted matches.
""";
