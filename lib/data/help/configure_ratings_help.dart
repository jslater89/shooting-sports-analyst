/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "package:shooting_sports_analyst/data/help/elo_help.dart";
import "package:shooting_sports_analyst/data/help/openskill_help.dart";
import "package:shooting_sports_analyst/data/help/points_help.dart";
import "package:shooting_sports_analyst/ui/widget/dialog/help/help_topic.dart";

const configureRatingsHelpId = "configure_ratings";
const configureRatingsHelpLink = "?configure_ratings";
final helpConfigureRatings = HelpTopic(
  id: configureRatingsHelpId,
  name: "Configuring ratings",
  content: _content,
);

const _content = """# Configuring Ratings

The ratings configuration page allows you to set up how ratings are calculated and manage match and project settings.
Tap the 'Advance' button at the top of the page to proceed to the ratings view. If the application detects that it is
necessary, you will be prompted to perform a full recalculation.

## Projects

A **rating project** is a collection of rating data stored in the database. Shooting Sports Analyst supports an arbitrary
number of rating projects. Each project's rating data is independent of the others.

The first time a project is loaded, Analyst must run a full calculation. On completion, the results of that calculation
are saved in the database. Subsequent loads of the project will use the previously-saved results, and new matches can be
appended to the end of the existing data without requiring a full recalculation.

Some configuration changes may require a full recalculation: changing the rating engine, adding matches that do not occur
after the last match in the existing data, or changing the set of rating groups included in the project, to name several.
Analyst does not always detect these changes, so the 'Force recalculate' checkbox can be used to force a full
recalculation.

## Rating Groups

A **rating group** is a collection of shooters who are rated against each other. Ratings are calculated within a rating
group, not between groups. Rating groups are currently defined by each supported sport. Changing rating groups does not
force a full recalculation. Any groups that were not present in the previous full calculation will not display any data
until a full recalculation is performed, but removing and restoring groups that appear in the previous full calculation
will function correctly.

## Algorithms

The following rating algorithms are supported:

* [**Elo**]($eloHelpLink) - Shooting Sports Analyst's default and best-tested rating system, a multiplayer generalization
of the [Elo rating system](https://en.wikipedia.org/wiki/Elo_rating_system) best known for its use in the chess world.
* [**OpenSkill**]($openskillHelpLink) - An open-source Bayesian rating system originally developed for use in online games.
It is slow to converge on the true skill level of competitors, and therefore underdeveloped relative to Elo in this
application.
* [**Points series**]($pointsHelpLink) - A cumulative rating system that assigns points to competitors based on match
results, optionally choosing the best N matches of those a competitor has participated in.

Information about each algorithm is available in the help topics linked above.

## Matches

The matches list to the right of the configuration lists the matches that will be included in the rating project.
The buttons above the list allow you to add matches to the project in various ways, sort the list (although matches
are always sorted temporally when performing calculations), and filter and sort the list.

Next to each match, a calendar toggle indicates whether or not the match is currently in progress. In-progress matches
may be treated differently by rating algorithms. The 'refresh' button re-fetches the match from its original source.
The minus button removes the match from the project.

## Menu Items

At the top right of the configuration page, buttons allow you to create a new project, save the current project (either
under its current name, or under a new name to make a copy), import and export projects, and view the additional actions menu.

The menu contains actions that permit you to modify previously-applied deduplication fixes, migrate pre-database projects to
the current database-backed format, and clear or reset certain elements of the project settings.""";