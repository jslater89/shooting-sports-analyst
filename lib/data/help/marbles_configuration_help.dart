/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/data/help/marbles_help.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/help/help_topic.dart';

const marblesConfigHelpId = "marbles_configuration_help";
const marblesConfigHelpLink = "?$marblesConfigHelpId";

final helpMarblesConfiguration = HelpTopic(
  id: marblesConfigHelpId,
  name: "Marble game configuration",
  content: _content,
);

const _content = 
"""# Marble Game Configuration

For general information on the marble game, see the [marble game help]($marblesHelpLink).

## Generic Configuration Options
* **Starting marbles**: the number of marbles competitors start with when they enter the rating set.
* **Match ante**: the percentage of their marbles competitors stake to enter a match.
* **Model**: the model to use for marble distribution.

## Relative Finish Distribution Models
The relative finish models are based on competitors' percentage finishes relative to one another.
Each of the following models calculates a sum of percentage finishes for all competitors, then
calculates the ratio of each competitor's finish percentage relative to this sum. For example, the
finishes (100, 99.4, 80.5) yield a sum of 279.9. The ratios are (100 ÷ 279.9, 99.4 ÷ 279.9, 80.5 ÷ 279.9) =
(0.357, 0.355, 0.287).

Here, the models differ, performing some mathematical transform on the ratios to calculate a final
share value. For instance, the power law model raises each ratio to its power parameter. For example,
a power of 2 yields (0.357^2, 0.355^2, 0.287^2) = (0.127, 0.126, 0.082). These values are summed (yielding
0.335 in our example), and the share sum is divided by each competitor's share value to determine the number
of marbles each competitor receives.

To finish our example, if the total stake for the match was 100 marbles, the competitors receive
100 × (0.127 ÷ 0.335, 0.126 ÷ 0.335, 0.082 ÷ 0.335) = (38, 38, 24) marbles.

### Power law
The power law model has one parameter: **power**, which controls the number to which each competitor's
initial finish ratio is raised. A higher power parameter generates a greater disparity in marbles received,
giving more to high finishers and fewer to low finishers.

### Sigmoid
The sigmoid model applies a logistic function to each competitor's initial finish ratio, yielding a curve
that starts at 0, grows slowly at first, grows rapidly through the midpoint, levels off, and asymptotically
approaches 1. The **midpoint** parameter controls where the curve is centered. The **steepness** parameter
controls how steep the middle section of the curve is, and how quickly it transitions from the steep middle
section to the asymptotic sections.

## Ordinal Finish Distribution Models
Ordinal finish models operate almost exactly like the relative finish models, but use a competitor's inverse
place as their raw score, rather than the relative finish ratio. For example, in a match with three competitors,
the ordinal places are (1, 2, 3), and the inverse places are (3, 2, 1).

Quickly running through the example above, again assuming a power law model with a power of 2, the transformed
inverse places are (3^2, 2^2, 1^2) = (9, 4, 1), for a total of 14 shares. Each competitor therefore receives
100 × (9 ÷ 14, 4 ÷ 14, 1 ÷ 14) = (64, 29, 7) marbles.

### Ordinal power law
The ordinal power law model has one parameter: **power**, which controls the number to which each competitor's
inverse place is raised. A higher power parameter generates a greater disparity in marbles received,
giving more to low finishers and fewer to high finishers.
""";