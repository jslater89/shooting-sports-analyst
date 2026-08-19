/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "package:shooting_sports_analyst/data/help/entries/configure_ratings_help.dart";
import "package:shooting_sports_analyst/data/help/entries/match_file_import_help.dart";
import "package:shooting_sports_analyst/data/help/entries/match_source_chooser_help.dart";
import "package:shooting_sports_analyst/data/help/entries/match_preps/match_prep_divisions_help.dart";
import "package:shooting_sports_analyst/data/help/entries/match_preps/match_prep_predictions_help.dart";
import "package:shooting_sports_analyst/data/help/entries/match_preps/match_prep_rating_links_help.dart";
import "package:shooting_sports_analyst/data/help/entries/match_preps/match_prep_squadding_help.dart";
import "package:shooting_sports_analyst/data/help/entries/prediction_games/prediction_games_help.dart";
import "package:shooting_sports_analyst/data/help/entries/ratings/ratings_view_help.dart";
import "package:shooting_sports_analyst/data/help/entries/results_help.dart";
import "package:shooting_sports_analyst/data/help/help_topic.dart";

const matchPrepsHelpId = "match_preps";
const matchPrepsHelpLink = "?$matchPrepsHelpId";

final helpMatchPreps = HelpTopic(
  id: matchPrepsHelpId,
  name: "Match preps",
  content: _content,
);

const _content =
"""# Match Preps

A **match prep** connects a rating project to the registration data for an upcoming match. It is
the workspace for linking registered competitors to ratings, browsing squads and divisions, and
generating stored prediction sets you can revisit or export.

Match preps require a rating project whose algorithm supports predictions. Open the list from the
home page ("Prepare for a future match"), or from the crystal-ball icon on the
[ratings view]($ratingsViewHelpLink) for the current project.

## Creating a Match Prep

Use the plus icon on the Match Prep list page. The new-match dialog asks for:

* **Project** — the rating project that supplies ratings and runs predictions. When opened from the
  ratings view, this is fixed to the current project; otherwise it defaults to the application-wide
  ratings context from settings, and can be changed with the edit button.
* **Match** — a future match from the local future-match database (see below).

Only one match prep may exist for a given project and match. If you try to create a duplicate, the
dialog warns you and disables Create.

## Future Matches and Registrations

Before you can create a match prep, the match's registration data must be in Analyst's future-match
database. When choosing a match, the chooser dialog can download registrations from the
[match source chooser]($matchSourceChooserHelpLink) (SSA Server and CSV import). Downloaded matches
are saved locally and reused by future preps. Registration data can also be
[imported]($matchFileImportHelpLink) from local files.

Each future match stores competitor names, divisions, classifications, member numbers (when known),
and squad assignments when the source provides them.

## Match Prep List

The list shows every match prep, or only those for one project when opened from the ratings view.
Each row shows the match name, date, and project name. Click a row to open that match prep. The
delete icon removes a match prep and its prediction sets. Deletion is blocked while a local
[prediction game]($predictionGamesHelpLink) still references the match prep.

## Match Prep Page

The page title is the future match name. Four tabs organize the workflow:

* **[Rating Links]($matchPrepRatingLinksHelpLink)** — link registrations to ratings in the project.
  Usually the first stop.
* **[Squadding]($matchPrepSquaddingHelpLink)** — squad cards when registration data includes squad
  numbers.
* **[Divisions]($matchPrepDivisionsHelpLink)** — read-only division rosters with sort options.
* **[Predictions]($matchPrepPredictionsHelpLink)** — create, compare, and export prediction sets;
  view odds and actual results when a match has been scored.

## Relationship to Other Features

Match preps use the same rating project you configure on the
[configuring ratings]($configureRatingsHelpLink) page. Predictions from a linked match prep can feed
**Rating-aware** match prediction display on the [results page]($resultsHelpLink) when viewing that
match with the same project as ratings context.

Local prediction games can attach to match preps and their prediction sets; that is why match preps
referenced by a game cannot be deleted.

## Tips and Limitations

* Prediction support depends on the rating algorithm. Algorithms without prediction support do not
  show the crystal-ball icon on the ratings view.
* Revisit rating links after registration updates, and create fresh prediction sets when the field
  changes materially.""";
