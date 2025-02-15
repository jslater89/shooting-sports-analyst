
import 'package:shooting_sports_analyst/ui/widget/dialog/help/help_topic.dart';

const broadcastHelpId = "broadcast_mode";
const broadcastHelpLink = "?$broadcastHelpId";

final HelpTopic helpBroadcastMode = HelpTopic(
  id: broadcastHelpId,
  name: "Broadcast mode",
  content: _content,
);

const _content =
"""# Broadcast Mode

Shooting Sports Analyst's broadcast mode is a tool to watch multiple leaderboards
in a given match at one time, highlighting new or interesting scores as they happen.

The user interface is arranged into two parts: the ticker and the scorecard grid.

## Ticker 
The ticker shows information about how soon the scores will update again, along with scrolling
'headline news' from the match: scores far above or below average, new stage wins,
and match lead changes. On the top left, the ticker also contains controls to pause,
resume, and configure automatic updates, and to manually refresh the scores. On the top
right, the ticker contains controls to configure the scorecard display. 'Time warp' allows
you to select a time in the past, and displays only scores occurring before that time,
so that you can review scores from earlier in the match. 'Card settings' allows you to
configure the height and width of scorecards, to select a prediction mode for incomplete
scores, and to configure highlight modes for scorecard cells. The '+ Row' and '+ Column'
buttons add new rows and columns to the scorecard grid.

## Scorecard Grid
The scorecard grid shows configured scorecards, and can be scrolled vertically (by scroll wheel)
and horizontally (by holding shift and using the scroll wheel), when the mouse is outside of a
scorecard. When the mouse is within a scorecard table, the scroll wheel scrolls the scorecard.
You can hold the control key while scrolling to disable scrolling inside a scorecard, and scroll
the grid instead.

## Scorecards
Scorecards show match scores in tabular format, with one row per shooter, one column for
match score, and one column for each stage. Each scorecard calculates a separate set of
match scores, so that the user can configure scorecards for different divisions, categories,
and classifications to be displayed side by side. Hovering over some text elements in a scorecard
cell will, depending on the current sport, show a tooltip with more information about the score:
when viewing a USPSA match, for instance, time and hits when hovering over the hit factor, and
raw stage points when hovering over the stage percentage.

In the scorecard header, the name is shown alongside the number of scores calculated and rows
displayed below. On the right are configuration buttons. The four arrows button moves the scorecard
into the row above or below, or swaps it with the scorecard to the left or right. The gear button
opens the scorecard settings dialog. The 'close' button removes the scorecard from the grid.
Empty rows and columns in the scorecard grid will be removed automatically.

The scorecard settings dialog contains fields to name the scorecard, to select the filters used to
calculate scores, and to select the filters used to determine which competitors are displayed in the
score table. Both scoring and display filters support Analyst's standard match score filters. Display
filters may additionally specify specific competitors and squads, and limit the scores displayed to the
top N competitors.

The per-scorecard settings dialog also contains a prediction mode selector, which overrides the global
prediction mode setting for that individual scorecard.""";
