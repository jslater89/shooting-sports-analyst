/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/ui/widget/dialog/help/help_topic.dart';

const appSettingsHelpId = "app-settings";
const appSettingsHelpLink = "?app-settings";
final helpAppSettings = HelpTopic(
  id: appSettingsHelpId,
  name: "App settings",
  content: _content,
);

const _content =
"""# App Settings

This dialog configures various settings for the application.

The log level dropdown changes the verbosity of the application's logging. Increased
verbosity (at the start of the list) will log information that may be useful when
submitting issue reports.

The deduplication alert checkbox will instruct the application to play an alert sound
when manual action is required for deduplication, and the ratings calculation complete
alert checkbox will instruct the application to play an alert sound when ratings
calculation is complete (provided calculation is required).

The ratings context setting identifies the project that should be used as a ratings
context when using broadcast mode to view a match.

The edit credentials button allows you to set credentials that some match sources
may required. Credentials are stored in the operating system's secure storage or
keychain.""";
