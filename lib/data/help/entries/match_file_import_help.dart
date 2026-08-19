/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "package:shooting_sports_analyst/data/help/entries/match_database_manager_help.dart";
import "package:shooting_sports_analyst/data/help/entries/match_preps/match_preps_help.dart";
import "package:shooting_sports_analyst/data/help/entries/results_help.dart";
import "package:shooting_sports_analyst/data/help/help_topic.dart";

const matchFileImportHelpId = "match_file_import";
const matchFileImportHelpLink = "?$matchFileImportHelpId";

final helpMatchFileImport = HelpTopic(
  id: matchFileImportHelpId,
  name: "Match file import",
  content: _content,
);

const _content =
"""# Match File Import

The match file import dialog loads match scores or registration data from files on disk into the
local database. Open it from the home page Import tile.

This is the primary way to bring local PractiScore exports and Analyst interchange files into the
application when server-side match sources are unavailable.

## Using the Dialog

Choose File opens a file picker. When a file is selected, Analyst auto-detects its format, processes
it, and writes status lines to the feedback panel. If processing succeeds, Import saves the result
to the database. After a successful import, Import becomes Reset, which clears the dialog so you can
import another file.

View opens the [results page]($resultsHelpLink) for processed score files. It is enabled only when
the import produced a completed match with scores, not for registration-only imports.

Close dismisses the dialog without saving unless you have already clicked Import.

## Supported Formats

### Score imports (match database)

These create a completed match record suitable for ratings, results viewing, and most analysis
features.

* PractiScore report.txt - a saved PractiScore web report for a hit-factor match. On PractiScore,
  use the browser find command (Ctrl+F) and search for "Web Report" on the match results
  page to locate the download.
* PractiScore .psc - a match export from the PractiScore scoring app, packaged as a zip containing
  match definition JSON.
* MIFF - Shooting Sports Analyst's match interchange format for scores. See the
  [MIFF specification](https://github.com/jslater89/shooting-sports-analyst/blob/develop/lib/api/miff/SPECIFICATION.md).

### Registration imports (future-match database)

These create a future match with registration rows. Future matches feed [match preps]($matchPrepsHelpLink)
and other pre-match workflows; they do not contain stage scores.

* RIFF - Analyst's registration interchange format. See the
  [RIFF specification](https://github.com/jslater89/shooting-sports-analyst/blob/develop/lib/api/riff/SPECIFICATION.md).
* PractiScore squadding page source (HTML) - saved HTML from a PractiScore squadding page. (In most browsers,
  right click the page and select "Save as..." to save the complete, loaded HTML file for processing.)
* PractiScore squadding page source .zip - a zip archive containing a file called `squadding.html`, as saved from
  the browser.

For PractiScore registration imports, Analyst reads match metadata from the HTML when possible. If
sport or date cannot be determined, the dialog asks you to select them before processing continues.

## File Type Dropdown

The File Type control lists all supported formats plus Auto-detect. After you choose a file,
Auto-detect selects the matching entry based on file contents. You can change the displayed type
manually, but processing always uses the format detected when the file was chosen. To force
a specific format, select it from the dropdown before choosing a file.

## After Import

Imported score matches appear in the [match database manager]($matchDatabaseManagerHelpLink) and can
be added to rating projects from the configuring ratings page. Imported future matches appear when
creating match preps or other flows that choose from the local future-match list.
""";
