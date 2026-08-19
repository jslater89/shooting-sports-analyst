/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "package:shooting_sports_analyst/data/help/help_topic.dart";

const matchPrepDivisionsHelpId = "match_prep_divisions";
const matchPrepDivisionsHelpLink = "?$matchPrepDivisionsHelpId";

final helpMatchPrepDivisions = HelpTopic(
  id: matchPrepDivisionsHelpId,
  name: "Divisions",
  content: _content,
);

const _content =
"""# Divisions

The Divisions tab is a read-only roster of registrations in each rating group, with a **Sort by**
dropdown for last name, rating, classification, or squad. The Row column reflects the current sort
order.

Member numbers prefer the linked rating's number when available. Click a linked row to open
shooter stats.""";
