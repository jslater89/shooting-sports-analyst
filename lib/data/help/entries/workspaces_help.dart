/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/data/help/help_topic.dart';

const workspacesHelpId = "workspaces";
const workspacesHelpLink = "?$workspacesHelpId";

final helpWorkspaces = HelpTopic(
  id: workspacesHelpId,
  name: "Workspaces",
  content: _content,
);

const _content =
"""# Workspaces

Workspaces let you keep several screens open in one instance of Shooting Sports Analyst
by way of a tab bar at the top of the window, for easy navigation between related tasks.
For instance, you can view a rating project, match results, and match predictions in
three separate tabs, switching between the tabs as needed rather than navigating out of
and into the various pages.

## Hiding the Tab Bar
A full-width 'expand/collapse' button with a chevron sits below the tabs (or at the
top of the window when the tabs are hidden). Click it to collapse or expand the tab bar.

## Opening and Closing
Use the **+** button on the workspace tab bar to open another workspace at the main
menu. Each workspace serves as an independent view into the application, with its own
navigation stack and history, while displaying the same underlying data.

You can have up to four workspaces. Closing a tab uses the **X** on the tab; the last
remaining workspace cannot be closed. Drag the handle on a tab to reorder workspaces.

## Tab Titles
Each tab shows a short label for its primary content, such as `Ratings · L2s Main LLR`
or `Match · Area 6 Championship`.

## Limitations
In general, workspaces should just work. The only expected limitation is that viewing
a rating set while recalculating the same rating set may cause the recalculation to fail,
or provide stale or erroneous data in the rating view.
""";
