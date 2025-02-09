import 'package:shooting_sports_analyst/ui/widget/dialog/help/help_topic.dart';
import 'package:shooting_sports_analyst/version.dart';

final helpAbout = HelpTopic(
  id: "about",
  name: "About",
  content: _content,
);

String _content =
"Shooting Sports Analyst v${VersionInfo.version}\n"
"MPL 2.0, except where noted\n\n"

"Shooting Sports Analyst is a desktop application for viewing, analyzing, and predicting USPSA match results. "
"Visit the repository at [https://github.com/jslater89/shooting-sports-analyst](https://github.com/jslater89/shooting-sports-analyst) "
"for more information.\n\n"

"USPSA, IDPA, PCSL, PractiScore, and other trade names or trademarks are used solely for descriptive or "
"nominative purposes, and their use does not imply endorsement by their respective rights-holders, or affiliation "
"between them and Shooting Sports Analyst. ";