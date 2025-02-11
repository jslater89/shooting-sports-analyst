/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/ui/widget/dialog/help/help_topic.dart';
import 'package:shooting_sports_analyst/version.dart';

const aboutHelpId = "about";
const aboutHelpLink = "?about";
final helpAbout = HelpTopic(
  id: aboutHelpId,
  name: "About",
  content: _content,
);

String _content =
"# About\n"
"\n"
"Shooting Sports Analyst is a desktop application for viewing, analyzing, and predicting USPSA match results. "
"Visit the repository at [https://github.com/jslater89/shooting-sports-analyst](https://github.com/jslater89/shooting-sports-analyst) "
"for more information.\n"
"\n"
"USPSA, IDPA, PCSL, PractiScore, and other trade names or trademarks are used solely for descriptive or "
"nominative purposes, and their use does not imply endorsement by their respective rights-holders, or affiliation "
"between them and Shooting Sports Analyst.\n"
"\n"
"Shooting Sports Analyst v${VersionInfo.version}\n"
"MPL 2.0, except where noted\n";