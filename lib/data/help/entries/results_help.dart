/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/data/help/help_topic.dart';

const resultsHelpId = "results";
const resultsHelpLink = "?$resultsHelpId";

final HelpTopic helpResults = HelpTopic(
  id: resultsHelpId,
  name: "Results page",
  content: _content,
);

const _content =
"""# Results Page

The results page is the main tool for viewing and analyzing match results. Scores for
the current match or stage are displayed in table form in the main part of the page,
formatted according to the style of the match's sport.

## Search and Filter
Above the results are the filter controls.

### Filter Dialog
The 'Filters' button opens a dialog that
controls the main scoring and display filters for the match. The main part of the
dialog allows filtering by power factor, division, and classification in either
'and' or 'or' mode: if the 'exclusive filters' checkbox is checked, competitors
must match power factor, division, and classification. If it is unchecked, competitors
must match any one of power factor, division, or classification. Sports that recognize
categories such as Lady or Junior may provide checkboxes for those categories, which
apply after other filters.

At the bottom of the dialog, the 'include 2nd gun' checkbox attempts to filter out
competitor reentries, and the 'score DQs' checkbox controls whether disqualified
competitors are scored on the stages they completed, or assigned zeroes on all
stages. For sports with squads, the 'squads' button at the bottom left allows selecting
squads to filter by. Sports may additionally provide presets for certain sets of filters,
for instance 'Locap' in USPSA.

### Stage Selector
The 'Results for...' dropdown allows for the selection of a particular stage or the
overall match results, and also allows for the selection of a subset of stages for
scoring.

### Sorting
Depending on the sport, scores may be sorted by a wide variety of properties. When sorting,
the 'row' column in the score table will display the position according to the sort, while
the 'place' column will display the position according to the scores calculated for
the current filters.

### Quick Search
This field provides quick filtering by name, and also supports a simple query language
for more advanced filtering. Queries prefixed with ? will be processed by the simple
query parser, which supports the following operations:

* <division, classification, or power factor name> - filter competitors that match the
given division, classification, or power factor.
* "<partial name>" - filter competitors that match the given quoted name, either first
or last.
* dq - (the literal string 'dq') show only disqualified competitors.
* !dq - hide disqualified competitors.
* dnf - show only DNF competitors.
* !dnf - hide DNF competitors.
* <condition> AND <condition> - competitors must match both query conditions.
* <condition-group> OR <condition-group> - a condition group is a group of conditions
connected by AND, or a single condition. Competitors must match at least one condition
group.

For example, ?"slater" OR open AND b will show everyone whose name contains 'slater',
as well as all Open B-class competitors.

## Ratings Context
If an application-wide ratings context has been selected in application settings, or if
you are viewing the match result from within a rating project, the result page will
be enhanced with rating information. A 'Rating' column in the scores list will show
each competitor's prematch rating, rating change, or postmatch rating. (Change modes
by clicking the 'rating' header.)

## Match Breakdown and Competitor Locations
The data table icon in the app bar will display a breakdown of the match, showing total
competitor counts by classification, division, and power factor.

The 'Competitor map' option in the three-dot menu at the far right of the app bar will
display a map of competitor locations based on either registration information (if available),
or from a ratings context if registrations do not have location information but a ratings
context is available.

## What-If Mode
The pencil icon in the app bar enters what-if mode, allowing you to edit competitor
information (name, division, and power factor, where relevant) when viewing overall
match results, and to edit stage scores when viewing stage results.

## Display Settings
The gear icon in the app bar shows display settings, some of which control scoring settings
and others of which determine which information is displayed in the table.

* **Available points count penalties** adjusts the points/total column so that penalties
  count for their penalty value against your points-on-target total.
* For USPSA and other fixed-time sports, **Improved fixed time available points** uses
  the highest score achieved on a stage as the 100% value, rather than the maximum number
  of points available on the stage.
* **Fantasy points mode** controls display of the fantasy points column. Fantasy points
  are assigned based on overall score, stage wins, raw time wins, and accuracy wins.
  'By division' calculates fantasy points for each division. 'Current filters' calculates
  fantasy points for all competitors currently displayed on the table.
* If a ratings context is available, **Rating display mode** changes the state of the
  Rating column on the table.
* **Match prediction mode** controls how scores are displayed for competitors who haven't
  finished the match.
    * **None** makes no changes to the recorded scores.
    * **High available** gives competitors 100% of the winner's score on unfinished stages.
      (For hit factor, 100% of the match points. For time plus, the current winner's time.
      For points scoring, the current winner's points.)
    * **Average stage finish** takes the average of a competitor's current stage percentages
      and gives them that percentage of the leader's score on each stage.
    * **Average finish in ratings** takes the average of a competitor's historical stage finishes
    and gives them that percentage of the leader's score on each stage, available only if a
    ratings context is present.
    * **Rating-aware**, when the ratings context supports predictions, uses a competitor's
    expected ratio against the field based on rating algorithm predictions to generate stage
    percentages. As more of the match is completed, up to 75% of the competitor's average
    stage finish is blended into the result.
""";
