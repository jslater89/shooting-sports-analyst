/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "package:shooting_sports_analyst/data/help/entries/match_database_manager_help.dart";
import "package:shooting_sports_analyst/data/help/entries/match_file_import_help.dart";
import "package:shooting_sports_analyst/data/help/entries/match_preps/match_preps_help.dart";
import "package:shooting_sports_analyst/data/help/entries/results_help.dart";
import "package:shooting_sports_analyst/data/help/help_topic.dart";

const matchSourceChooserHelpId = "match_source_chooser";
const matchSourceChooserHelpLink = "?$matchSourceChooserHelpId";

final helpMatchSourceChooser = HelpTopic(
  id: matchSourceChooserHelpId,
  name: "Match source chooser",
  content: _content,
);

const _content =
"""# Match Source Chooser

The match source chooser dialogs search online sources for completed matches or upcoming-match
registrations. They share the same basic layout wherever they appear: a source dropdown at the top,
then source-specific search controls and results.

Open the combined dialog from the home page **Download matches from Internet sources** tile. Narrower
variants appear when adding matches from the [match database manager]($matchDatabaseManagerHelpLink)
or future matches when creating a [match prep]($matchPrepsHelpLink).

For files on disk, use [match file import]($matchFileImportHelpLink) instead.

## Match Tab

The Match tab finds completed matches with scores. Selecting a result opens it for viewing on the
[results page]($resultsHelpLink). When the source supports background download, a download icon on
each row saves the match to the local database without leaving the dialog. For some sources, a long
press may also save the match to the database.

Available match sources depend on your build and configuration.

The **SSA Server** is always available: Shooting Sports Analyst's server index. Search by name or
keywords, with **Match all** (every word must appear) or **Match any** (any word may appear) and
sort by name or date.

Some sources show a warning banner when they may not function correctly.

## Future Match Tab

The Future Match tab finds registration data for upcoming matches. Selecting a result downloads the
match and saves it to the local future-match database for use in match preps and related workflows.
These records contain registrations, not stage scores.

Sources include:

* **SSA Server** — search and download registration sets the same way as on the Match tab.
* **CSV Importer** — attach registrations from a PractiScore match management CSV file export
  to an existing future match in the local database. This overwrites existing registrations on
  that match. CSV files do not carry match metadata; create or download a future match shell
  first. Users can create a future match from the [import dialog]($matchFileImportHelpLink) as
  a target for CSV imports.

When opened from the home page, a downloaded future match is saved automatically and confirmed with
a snackbar.

## Source Selection

The source dropdown lists every implemented source for that tab. Analyst remembers your last choice
per tab and restores it the next time you open the dialog.

## Search Results

Tap a row to fetch and use that match (open for viewing on the Match tab, or download on the Future
Match tab). Where supported, use the download icon, or long-press on some sources, to save to the
database while staying in the chooser. This is useful when adding multiple matches without viewing
each one in between.

Note that launching a match from the chooser does not save it to the database. You must use the
'save to database' icon in the results page]($resultsHelpLink) to save it.

Errors from the source appear in a separate error dialog with the message from the server or parser.
""";
