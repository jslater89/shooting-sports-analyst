/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/data/help/entries/configure_ratings_help.dart';
import 'package:shooting_sports_analyst/data/help/entries/deduplication_help.dart';
import 'package:shooting_sports_analyst/data/help/help_topic.dart';

const recalculationHelpId = "recalculation";
const recalculationHelpLink = "?recalculation";
final helpRecalculation = HelpTopic(
  id: recalculationHelpId,
  name: "Recalculation",
  content: _content,
);

const _content = """# Recalculation

In normal operation, Shooting Sports Analyst's rating engine will append
new matches to a rating project: calculations use the current ratings as
a starting point, and results from the new matches are added to that point.
However, in some cases, such as algorithm updates, manual [deduplication]($deduplicationHelpLink)
actions, or matches added prior to the most recent match in the project,
a full recalculation may be necessary for accurate ratings.

The 'full recalculation' checkbox on the [configure ratings]($configureRatingsHelpLink)
screen can be used to force a full recalculation. This will delete all existing
rating data and recalculate from scratch, starting at the first match.

For recalculations which do not change the set of competitors included in the
project, the 'skip deduplication' checkbox can be used to skip the (typically
time-consuming) deduplication step. If you are adding new matches, you almost
certainly do not want to skip deduplication, but if you are recalculating because
of algorithm changes or manual deduplication updates, skipping deduplication
will save substantial calculation time.
""";
