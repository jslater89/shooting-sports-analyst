/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "package:shooting_sports_analyst/ui/widget/dialog/help/help_topic.dart";

const configureRatingsHelpId = "configure_ratings";
const configureRatingsHelpLink = "?configure_ratings";
final helpConfigureRatings = HelpTopic(
  id: configureRatingsHelpId,
  name: "Configuring Ratings",
  content: _content,
);

const _content =
"# Configuring Ratings\n"
"\n"
"The ratings configuration page allows you to set up how ratings are calculated and manage shooter data.\n"
"\n"
"## Projects\n"
"\n"
"A **rating project** is a collection of rating data stored in the database. Shooting Sports Analyst supports "
"an arbitrary number of rating projects. Each project's rating data is independent of the others.\n"
"\n"
"The first time a project is loaded, Analyst must run a full calculation. On completion, the results of that "
"calculation are saved in the database. Subsequent loads of the project will use the previously-saved results, "
"and new matches can be appended to the end of the existing data without requiring a full recalculation.\n"
"\n"
"Some configuration changes may require a full recalculation: changing the rating engine, adding matches that "
"do not occur after the last match in the existing data, or changing the set of rating groups included in the "
"project, to name several. Analyst does not always detect these changes, so the 'Force recalculate' checkbox "
"can be used to force a full recalculation.\n"
"\n"
"## Rating Groups\n"
"\n"
"A **rating group** is a collection of shooters who are rated against each other. Ratings are calculated "
"within a rating group, not between groups. Rating groups are currently defined by each supported sport.\n";

