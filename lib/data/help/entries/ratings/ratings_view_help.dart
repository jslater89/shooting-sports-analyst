/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "package:shooting_sports_analyst/data/help/entries/configure_ratings_help.dart";
import "package:shooting_sports_analyst/data/help/entries/invitational_invites_help.dart";
import "package:shooting_sports_analyst/data/help/entries/match_heat_help.dart";
import "package:shooting_sports_analyst/data/help/entries/match_preps/match_preps_help.dart";
import "package:shooting_sports_analyst/data/help/entries/rating_reports_help.dart";
import "package:shooting_sports_analyst/data/help/entries/rating_set_help.dart";
import "package:shooting_sports_analyst/data/help/entries/results_help.dart";
import "package:shooting_sports_analyst/data/help/entries/scalers_and_distributions_help.dart";
import "package:shooting_sports_analyst/data/help/help_topic.dart";

const ratingsViewHelpId = "ratings_view";
const ratingsViewHelpLink = "?$ratingsViewHelpId";

final HelpTopic helpRatingsView = HelpTopic(
  id: ratingsViewHelpId,
  name: "Ratings view",
  content: _content,
);

const _content =
"""# Ratings View

The ratings view is the main tool for browsing calculated ratings in a rating project. It is
reached from the [configuring ratings]($configureRatingsHelpLink) page after a project has been
loaded or calculated. The page title shows the project name.

Each tab corresponds to a rating group in the project, typically a division within the sport
but sometimes a combination of divisions. Ratings are calculated within a rating group, not
between groups. Switch tabs to view a different group.

## Search and Filter

Above the ratings table are the main filter controls.

### Sorting
The sort dropdown controls the order of rows in the table. Available sort modes depend on the
rating algorithm in use. Common options include rating, last change, classification, and
algorithm-specific columns such as error or dispersion. The place column always reflects the
current sort order.

### Quick Search
The search field filters the displayed ratings. Press Enter or click the arrow icon to apply
the search. Plain text matches against competitor name or member number (including alternate
member numbers from deduplication). Queries prefixed with ? use a subset of the same
simple query language as the [results page]($resultsHelpLink):

* <classification name> — filter competitors that match the given classification.
* "<partial name>" — filter competitors that match the given quoted name, either first or last.
* <condition> AND <condition> — competitors must match both query conditions.
* <condition-group> OR <condition-group> — a condition group is a group of conditions connected
  by AND, or a single condition. Competitors must match at least one condition group.

### Minimum History and Maximum Age
Min. Matches (or Min. Stages, when the project rates by stage) hides competitors with fewer than
the given number of rating events from the display. They remain in the underlying data.

Max. Age hides competitors whose last activity was more than the given number of days before
the reference match date. The default is the number of days since January 1 of the previous
calendar year.

### Filter Dialog
The filter icon opens a dialog with additional demographic filters: Lady, age categories, and
other sport-specific categories. These apply on top of the search and history filters.

## Ratings Table

The table columns depend on the rating algorithm. Typical columns include member number,
classification, name, rating, last change, and algorithm-specific uncertainty or trend
measures. Some algorithms fade rows for competitors who have not shot recently.

Click a row to open the competitor detail dialog, which shows rating history, per-event
changes, career statistics, and links to comparison tools and individual match results.

## App Bar Actions

If the rating algorithm supports predictions, the crystal-ball icon opens the [match prep]($matchPrepsHelpLink)
list for creating future match predictions from this project.

The bar-chart icon opens division or group statistics for the currently displayed ratings,
using any active rating scaler.

The eye icon opens the hidden shooters editor. Hidden shooters continue to participate in
rating calculations but are omitted from the display. This is useful, for example, for hiding
non-local shooters from a local ratings list.

The info icon opens [rating reports]($ratingReportsHelpLink) from the latest calculation.

## Three-Dot Menu

Set date for trend sets the reference date used when sorting by trend or change-based columns.
Ratings are compared to their values at that date rather than their current values.

Export ratings as CSV and Export ratings as JSON each produce a zip archive containing one file
per rating group, respecting the current filters.

Fix data entry errors opens the member number correction list for the project.

View match results opens a match chooser and navigates to the results page for the selected
match, with this project available as the ratings context.

View match heat opens the [match heat]($matchHeatHelpLink) graph for the project.

Generate invitational invites opens the [invitational invite builder]($invitationalInvitesHelpLink) for the current project.

Choose rating sets opens the [rating sets]($ratingSetsHelpLink) manager. When one or more rating
sets are active, only competitors matching at least one set are shown.

Miscellaneous settings opens display options for [rating scalers and distributions]($scalersAndDistributionsHelpLink).
A rating scaler remaps displayed rating values: for example, to a standardized 0-2000 scale or
a z-score — without changing the underlying stored ratings.""";
