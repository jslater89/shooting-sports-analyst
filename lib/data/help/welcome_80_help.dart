/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/data/help/deduplication_help.dart';
import 'package:shooting_sports_analyst/data/help/uspsa_deduplicator_help.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/help/help_topic.dart';

const welcome80HelpId = "welcome80";
const welcome80HelpLink = "?welcome80";
final helpWelcome80 = HelpTopic(
  id: welcome80HelpId,
  name: "Welcome to 8.0",
  content: _content,
);

const _content =
"""# Welcome to Shooting Sports Analyst 8.0!

This release represents more than a year of sustained work and more than 15,000 new lines of
code, focusing on support for multiple sports, improved match import, and database storage
for match results and ratings. This foundational work paves the way for new enhancements in
future releases, centering on the use of ratings to provide context in other areas of the
application.

This help page provides a brief tour of the new features, including notes on any gotchas or
breaking changes from the 6.0 and 7.0 series of releases. You will only see it automatically
once, but I will attempt to keep it up to date as the alpha process progresses.

## This Help System

Instead of writing documentation in various READMEs and blog posts, I decided to build
a help system directly into the application. The index to the left lists all available
topics, and where relevant help topics exist, 'help' icons in the application will link
to them, launching this window on the correct page.

Analyst is a very complicated tool, and I expect the help system will continue to grow
as the 8.0 release cycle proceeds.

## Known Issues

Among others, the following issues are known:

* Category filters are not yet supported in the rating view screen.
* Repeatedly migrating old rating projects with the same name override yields multiple
  projects with the same name.
* There are a few places where the ratings view UI is a bit slow.
* Member number mappings, data entry fixes, and blacklist entries migrated from old
  rating projects may not work as expected.
* Match score viewing for IDPA and PCSL may have some flaws in some cases.

Please report other issues via [Discord](https://discord.gg/rqHh7PVMNA) or
[GitHub](https://github.com/jslater89/shooting-sports-analyst/issues).

## Database Storage

A quirk of the 7.0 releases is that matches for ratings and standalone match results were
stored differently: ratings used the match cache system dating back to 6.0 and earlier,
while standalone matches used the match database. 8.0 unifies match storage: all data
comes from the database.

While the old match cache was stored in your user directory, the new database is stored
in the 'db' directory in the application directory. Storage is _no longer shared_ between
multiple instances of the application located in different directories. A configuration
option to use a shared directory is planned for a future release.

### Match Migration
To migrate matches from the match cache to the database, open the 'manage match database'
screen from the home page, and use the copy icon in the top right corner. In the database,
matches are identified by their identifier from the match source (at the moment, PractiScore
only), so the migration process can be repeated without creating duplicate matches.

### Rating Project Migration
To migrate a rating project, open the 'generate ratings' screen from the home page, then
use the 'migrate from old project' option in the dropdown menu in the top right corner.
Migration will not copy rating data, but will copy the project configuration. Due to changes
in member number handling and improvements to the [deduplication]($deduplicationHelpLink)
process, you may need to make substantial changes to the project configuration on your
first calculation of a new project.

## Rating Calculations

First, the bad news: full rating calculations are much, much slower than they were in 7.0.
Whereas a full run of the 470-match L2s-since-2018 ratings takes less than a minute in 7.0,
the same project in 8.0 takes between 10 and 20 minutes, at present. There is still some
optimization meat on the bone, but even once 8.0 is as optimized as 7.0 was (and 7.0 was
seriously optimized), I expect that the calculation times in 8.0 will still be substantially
longer.

The good news is that, because ratings are persisted across application restarts, you
should not _need_ to perform full calculations very often. The two most common scenarios
(starting the application to look at ratings, and appending matches that all occur after
the most recently calculated ratings) are much faster in 8.0, because they no longer
require calculating ratings entirely from scratch every time.

### Available Rating Algorithms
All of the rating algorithms that were available in 7.0 are also available in 8.0, and
should work the same way. Elo numbers will likely be somewhat different, and may not
be stable from release to release during the alpha period, since connectivity is handled
substantially differently in 8.0 vs. 7.0, and the precise details of the algorithm are
not yet settled.

### Non-USPSA Ratings
... are not quite ready yet, but the path from here to there is clear. The largest
obstacle is writing a generic shooter deduplicator, but given that most non-USPSA
sports have a substantially less dumb member numbering system than USPSA, that
task is less daunting than it was for the USPSA case.

### Deduplication
Shooter deduplication has been substantially improved in 8.0, and can handle a dramatically
wider array of situations than in 7.0. All deduplication occurs at the beginning of a
project load, so that you don't need to pay attention during the entire rating process.

The deduplication process has [its own help topic]($deduplicationHelpLink), which you can
also view via the help button in the deduplication window during project loading. The
deduplication window shows dramatically more information than the previous deduplication
UI, and does a much better job at guiding you through the process. It is also heavily
tested, with 27 separate scenarios covered by automated tests.

The [USPSA deduplicator]($uspsaDeduplicatorHelpLink) has its own help topic as well,
which goes into specifics about the peculiarities of the process as applied to USPSA.

### The Loading Screen
Since rating calculations take longer, the loading screen has been improved to provide
more detail on what the rating engine is doing at a particular time, and about how much
progress it has made against the expected total. An upper progress bar shows the total
completion status, while a lower progress bar shows the status of the current task.
""";