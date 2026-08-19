/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "package:shooting_sports_analyst/data/help/help_topic.dart";

const matchPrepSquaddingHelpId = "match_prep_squadding";
const matchPrepSquaddingHelpLink = "?$matchPrepSquaddingHelpId";

final helpMatchPrepSquadding = HelpTopic(
  id: matchPrepSquaddingHelpId,
  name: "Squadding",
  content: _content,
);

const _content =
"""# Squadding

When registrations include squad numbers, the Squadding tab displays one card per squad. Squads are
grouped into schedules: single-digit squads are treated as one schedule, and longer squad numbers
are grouped by their leading digit (for example, 101-103 versus 201-203).

Each card lists competitors on that squad with division and linked rating; click a rated competitor
for shooter stats.

The squadding layout assumes USPSA-style squad numbering. Unusual schemes may appear as a single
schedule.""";
