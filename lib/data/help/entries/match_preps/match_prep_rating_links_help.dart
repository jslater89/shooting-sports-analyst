/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "package:shooting_sports_analyst/data/help/help_topic.dart";

const matchPrepRatingLinksHelpId = "match_prep_rating_links";
const matchPrepRatingLinksHelpLink = "?$matchPrepRatingLinksHelpId";

final helpMatchPrepRatingLinks = HelpTopic(
  id: matchPrepRatingLinksHelpId,
  name: "Rating links",
  content: _content,
);

const _content =
"""# Rating Links

The Rating Links tab is usually the first stop on a match prep page. Registrations must be linked
to ratings in the project before predictions can include a competitor.

The tab has one sub-tab per rating group in the project.

## Filters and Automatic Matching

Above the table:

* **Show linked** and **Show unlinked** filter which registrations appear.
* **Match from database** attempts automatic linking for unmatched registrations in the current
  group, using name, division, and classification. Successful matches write member numbers and
  registration mappings to the database.

## Table Columns and Actions

Each row shows registration name, class, division, and member number, whether the link was created
manually (checkmark in the Manual column), the linked rating (click to open shooter stats), and
link/unlink actions.

Use the link icon to search for a rating manually; the dialog pre-fills a surname search when it
can parse one from the registration name. Unlinked rows may show "(N candidates)" when automatic
matching found possible ratings, or "(possible nickname)" when the name looks like a nickname.

Each rating can be linked to at most one registration, and each registration to at most one rating.

## Tips

Revisit Rating Links after registration updates. New competitors need links before they appear in
predictions.

Automatic matching is conservative. Review ambiguous rows — especially similar names or missing
member numbers — before relying on predictions.""";
