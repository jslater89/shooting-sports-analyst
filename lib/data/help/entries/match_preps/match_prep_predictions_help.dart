/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "package:shooting_sports_analyst/data/help/entries/match_preps/match_prep_rating_links_help.dart";
import "package:shooting_sports_analyst/data/help/help_topic.dart";

const matchPrepPredictionsHelpId = "match_prep_predictions";
const matchPrepPredictionsHelpLink = "?$matchPrepPredictionsHelpId";

final helpMatchPrepPredictions = HelpTopic(
  id: matchPrepPredictionsHelpId,
  name: "Predictions",
  content: _content,
);

const _content =
"""# Predictions

Prediction sets are named snapshots of algorithm-generated finish predictions for the current
registration links. They are stored with the match prep so you can compare how the field looked at
different times (for example, before and after a major registration update).

Competitors without a linked rating in a group are omitted from that group's predictions. Link
registrations on the [Rating Links]($matchPrepRatingLinksHelpLink) tab first.

## Controls

At the top of the tab:

* **Prediction set** — choose an existing set from the dropdown.
* **CREATE** — generate a new set using the current links. The default name is the current date and
  time.
* **DELETE** — remove the selected set.
* **EXPORT** — download a zip of CSV files, one per rating group, containing full prediction data.
* **SETTINGS** — (USPSA only) configure Limited Optics / Carry Optics handling (see below).

Below the controls, tabs appear for each non-excluded rating group. The prediction table matches the
standalone prediction view: predicted place ranges (low, median, high), a whisker plot, and an
**ODDS** button that opens a Monte Carlo wager dialog for the current group. Click a row for
shooter stats.

## Comparing to Actual Results

When a match result has been linked to this future match (link icon in the match prep app bar),
the table also shows each competitor's actual finish place and match percentage so you can compare
predictions to outcomes.

Linking a result does not change rating links or regenerate prediction sets; it only overlays
actual scores on existing predictions. Use the unlink icon to remove the association without
deleting registration or prediction data.

On the box and whisker plots, the blue line shows the 100% datum on competitors who are expected
to finish at or near the top of the scoreboard, while the green line shows a competitor's actual
finish.

## USPSA Prediction Settings

For USPSA match preps, the SETTINGS button opens two options:

* **Combine LO/CO for LO and CO predictions** — when enabled, Limited Optics and Carry Optics
  registrations use the combined LO/CO rating group for predictions instead of separate LO and CO
  ratings.
* **Generate LO/CO predictions** — when enabled, an additional combined Limited Optics / Carry
  Optics prediction group is included. When disabled, that group is excluded from new prediction
  sets.

Changing these settings affects newly created prediction sets. Existing sets retain the
configuration they were created with.

## Tips

Creating a new prediction set does not update older sets. Make a fresh set when the field or
links change materially.""";
