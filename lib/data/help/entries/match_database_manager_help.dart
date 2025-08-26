/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/data/help/help_topic.dart';

const matchDatabaseManagerHelpId = "match_database_manager";
const matchDatabaseManagerHelpLink = "?match_database_manager";

final helpMatchDatabaseManager = HelpTopic(
  id: matchDatabaseManagerHelpId,
  name: "Match database manager",
  content: _content,
);

const _content =
"""# Match Database Manager

This screen lists all matches currently in the database, and allows filtering based on name and date.
Name-based filtering operates as a prefix match on each word: 'ate' will not match 'State', but 'cha'
will match 'Championship'. Additional filter options are planned.

This screen will eventually be enhanced to allow deleting matches, and eventually to allow editing of
both match details and match scores.

## Match Migration

To migrate matches from the match cache (previously saved from 7.0 rating projects), use the copy icon
in the top right corner. In the database, matches are identified by their identifier from the match source
(at the moment, PractiScore only), so the migration process can be repeated without creating duplicate
matches.

## Database Statistics

The database statistics dialog, accessible from the action icon in the top right corner, shows the
counts of various events stored in the database and their average size. The 'load project statistics'
button will show a breakdown of the approximate size of each rating project in the database. This
approximation does not account for algorithm-specific differences in data storage: an Elo rating
event contains more data than a points rating event, and has a correspondingly larger size on disk,
but both are treated the same by the approximation.

The 'total size' line at the bottom of the dialog shows the total size of the database, and the
amount of space used as a percentage of the maximum allowed size (currently 32 gigabytes).
""";
