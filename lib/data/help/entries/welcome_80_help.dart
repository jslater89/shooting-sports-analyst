/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/data/help/entries/deduplication_help.dart';
import 'package:shooting_sports_analyst/data/help/entries/icore_deduplicator_help.dart';
import 'package:shooting_sports_analyst/data/help/entries/match_heat_help.dart';
import 'package:shooting_sports_analyst/data/help/entries/uspsa_deduplicator_help.dart';
import 'package:shooting_sports_analyst/data/help/help_topic.dart';

const welcome80HelpId = "welcome80";
const welcome80HelpLink = "?welcome80";
final helpWelcome80 = HelpTopic(
  id: welcome80HelpId,
  name: "Welcome to 8.0",
  content: _content,
);

const _content =
"""# Welcome to the Shooting Sports Analyst 8.0 beta!

This release represents more than a year of sustained work and nearly 20,000 new lines of
code, focusing on support for multiple sports, improved match import, and database storage
for match results and ratings. This foundational work paves the way for new enhancements in
future releases, centering on the use of ratings to provide context in other areas of the
application.

This help page provides a brief tour of the new features, including notes on any gotchas or
breaking changes from the 6.0 and 7.0 series of releases. You will only see it automatically
once, but I will attempt to keep it up to date as the alpha process progresses.

## Known Issues

There are very likely to be issues in this release, but at the time of writing, I don't
know of any that are serious or consistent enough to list here.

Please report any issues you discover via [Discord](https://discord.gg/rqHh7PVMNA) or
[GitHub](https://github.com/jslater89/shooting-sports-analyst/issues).

## This Help System

Instead of writing documentation in various READMEs and blog posts, I decided to build
a help system directly into the application. In various places throughout the application,
you will see a circle-question-mark 'help' icon. Clicking it will open this window and
show the relevant help topic. The index to the left lists all available topics.

Analyst is a very complicated tool, and I expect the help system will continue to grow
as the 8.0 release cycle proceeds.

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
longer. (Please note that, owing to certain issues with Windows filesystems, calculations
may take longer on Windows than on other platforms.)

The good news is that, because ratings are persisted across application restarts, you
should not _need_ to perform full calculations very often. The two most common scenarios
(starting the application to look at ratings, and appending matches that all occur after
the most recently calculated ratings) are much faster in 8.0, because they no longer
require calculating ratings entirely from scratch every time. Even if you miss a recent
match and append matches that occur after it, the application now supports rolling back
ratings to an earlier date. You can roll back to before the match you missed, append it,
and append the remaining matches that occur after it, in lieu of performing a full
calculation.

### Available Rating Algorithms
All of the rating algorithms that were available in 7.0 are also available in 8.0, and
should work the same way. Elo numbers will likely be somewhat different, and may not
be stable from release to release during the beta period, since connectivity is handled
substantially differently in 8.0 vs. 7.0, and the precise details of the algorithm are
not yet settled.

### Non-USPSA Ratings
... more or less work, although they have only been tested with IDPA and ICORE. Time-plus
ratings seem to work better with much higher place weight/lower percent weight than hit
factor ratings, as percentages are more sensitive to small variations in time-plus scoring,
particularly on short stages.

### Deduplication
Shooter deduplication has been substantially improved in 8.0, and can handle a dramatically
wider array of situations than in 7.0. All deduplication occurs at the beginning of a
project load, so that you don't need to pay attention during the entire rating process.

The deduplication process has [its own help topic]($deduplicationHelpLink), which you can
also view via the help button in the deduplication window during project loading. The
deduplication window shows much more information than the previous deduplication
UI, and does a much better job at guiding you through the process. It is also heavily
tested, with more than 50 separate scenarios covered by automated tests.

The [USPSA deduplicator]($uspsaDeduplicatorHelpLink) has its own help topic as well,
which goes into specifics about the peculiarities of the process as applied to USPSA.
So also does the [ICORE deduplicator]($icoreDeduplicatorHelpLink).

IDPA deduplication is not yet supported.

### The Loading Screen
Since rating calculations take longer, the loading screen has been improved to provide
more detail on what the rating engine is doing at a particular time, and about how much
progress it has made against the expected total. An upper progress bar shows the total
completion status, while a lower progress bar shows the status of the current task.

## Match Heat
Accessible from a ratings view page, the match heat view shows a scatter plot of match
size vs. match heat. More information is available in the [match heat help topic]($matchHeatHelpLink).
""";
