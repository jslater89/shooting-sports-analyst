/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/ui/widget/dialog/help/help_topic.dart';

const ratingEventHelpId = "rating_event";
const ratingEventHelpLink = "?rating_event";

final helpRatingEvent = HelpTopic(
  id: ratingEventHelpId,
  name: "Rating events",
  content: _content,
);

const _content =
"# Stage and Match Rating Events\n"
"\n"
"Shooting Sports Analyst can calculate ratings in two modes: by stage, or by match. In both the UI "
"and the help system, the term **rating event** is used to refer to either a stage or a match, depending "
"on the mode selected.\n"
"\n"
"The default is by stage. Calculating ratings on a stage-by-stage basis leads to a slightly larger amount "
"of instability, and slightly reduces the observed predictive power of Elo ratings. On the other hand, "
"this mode allows ratings to be much more responsive, more quickly arriving at a level near a competitor's "
"true skill.\n"
"\n"
"Calculating ratings match-by-match has the opposite effect. Ratings are more stable and more predictive, but "
"take much longer to converge on a competitor's true ability.";