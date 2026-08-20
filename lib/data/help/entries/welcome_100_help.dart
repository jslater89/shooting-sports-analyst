/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/data/help/entries/invitational_invites_help.dart';
import 'package:shooting_sports_analyst/data/help/entries/latent_log_help.dart';
import 'package:shooting_sports_analyst/data/help/entries/local_mcp_server_help.dart';
import 'package:shooting_sports_analyst/data/help/entries/match_file_import_help.dart';
import 'package:shooting_sports_analyst/data/help/entries/match_preps/match_preps_help.dart';
import 'package:shooting_sports_analyst/data/help/entries/prediction_games/prediction_games_help.dart';
import 'package:shooting_sports_analyst/data/help/help_topic.dart';

const welcome100HelpId = "welcome100";
const welcome100HelpLink = "?welcome100";
final helpWelcome100 = HelpTopic(
  id: welcome100HelpId,
  name: "Welcome to 10.0",
  content: _content,
  hidden: false,
);

const _content =
"""# Welcome to Shooting Sports Analyst 10.0!

Shooting Sports Analyst crossed the 150,000 lines-of-code mark on the way to this release:
it continues to grow more capable and more feature-laden by the day. Much of that work was
under the hood to enable the [Shooting Sports Analyst website](https://www.shootingsportsanalyst.com),
but just as much of it went into the application itself. This help page provides a brief tour
of new features and changes. You will only see it automatically once, but I may keep it up to
date as the 10.0 release cycle continues.

## Match Sources
Since the 8.0 release, PractiScore has substantially clamped down on third-party access to
score information. While there are some mirrors of which I'm aware, none are currently public.
The Shooting Sports Analyst server will provide scores for USPSA major matches and most ICORE
major matches. If you want to analyze your own local matches, you can use the updated Import menu
to import PractiScore web reports on hit factor matches. (Ctrl+F for "Web Report" on a PractiScore
match result page.)

## Improved Local Imports
The [local-import option]($matchFileImportHelpLink) on the main menu has been enhanced. It now supports all the formats that
Shooting Sports Analyst is currently able to import, including:

* Analyst's own [MIFF](https://github.com/jslater89/shooting-sports-analyst/blob/develop/lib/api/miff/SPECIFICATION.md)
  and [RIFF](https://github.com/jslater89/shooting-sports-analyst/blob/develop/lib/api/riff/SPECIFICATION.md) formats
  for match scores and registrations, respectively.
* PractiScore web report files.
* PractiScore .psc files, as exported from the PractiScore app on scoring tablets.
* PractiScore squadding pages (e.g. https://practiscore.com/match-slug/squadding), with optional user-entered
  sport and date information.

Stop by the [Shooting Sports Analyst Discord](https://discord.gg/rqHh7PVMNA) for help on getting your
data into Analyst!

## Rating Algorithms
New in 10.0 is the [Latent Log-Ratio]($latentLogHelpLink) algorithm, which uses a log cancellation
trick and some field-level statistical techniques to determine how well a winner shot on a given day
and update ratings in light of that: unlike Elo and Glicko, which suffer to some extent from a
pathology where the winner having a great day depresses everyone's percentages and therefore their
ratings, even if everyone else also performed above par.

## Match Preps
New since 8.0, match preps elevate pre-match predictions to a first-class feature of the application,
allowing you to more permanently connect ratings to match registrations, view squadding information
where available, and make predictions for upcoming matches. Read the [Match Preps]($matchPrepsHelpLink)
help page for more information.

## Local Prediction Games
The [canonical Prediction Game](https://www.shootingsportsanalyst.com/prediction-game/1/leaderboard) runs
on the Shooting Sports Analyst server, but in developing and testing it, I built largely the same user
experience into the desktop app. Compete with your friends on local match data or (for benefactor backers)
on your own copy of the major matches dataset. See the [Prediction games]($predictionGamesHelpLink) help
page for how local games work.

## Invitational Generator
As part of research work on the 2027 Cardinal Cup, I built out some infrastructure for generating invitations
to an invitational match based on prior match finishes and ratings. Thanks to the wonders of AI-assisted
development, that work is now available with a user interface inside of ratings projects. See the
[invitational invites]($invitationalInvitesHelpLink) help page for more.

## Local MCP Server
Shooting Sports Analyst now supports a local MCP server, allowing you to connect AI agents to the application.
The server supports read-only access to rating data, including match scores associated with a rating project,
along with current and historical ratings. See the [local MCP server]($localMcpServerHelpLink) help page for more.
""";