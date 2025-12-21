/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/data/help/help_topic.dart';

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

## Theme mode
This setting controls the theme mode of the application. 'System' uses the operating
system's preferred light or dark mode.

## UI scale factor
This setting controls the scale factor of the application's UI. Increasing the scale
factor will make the UI larger, and decreasing the scale factor will make the UI smaller.

## Log level
The log level dropdown changes the verbosity of the application's logging. Increased
verbosity (at the start of the list) will log information that may be useful when
submitting issue reports.

## Deduplication and ratings complete alerts
The deduplication alert checkbox will instruct the application to play an alert sound
when manual action is required for deduplication, and the ratings calculation complete
alert checkbox will instruct the application to play an alert sound when ratings
calculation is complete (provided calculation is required).

## Prefer SSA server source
Enabling this setting will cause the application to prefer the configured Shooting Sports
Analyst server for match data, regardless of the source specified in the match record.

## Auto-import
The auto-import directory specifies a directory that the application will watch for match
data files. When a supported file (.miff.gz, .miff, .riff.gz, .riff, .psc, .zip) is added
to that directory, the application will automatically attempt to import the file.

The 'delete after success' checkbox controls whether the application will delete imported
files after successful imports.

## Ratings context
The ratings context setting identifies the project that should be used as a ratings
context when viewing match results outside of the ratings section of the UI.

## Credentials
The edit credentials button allows you to set credentials that some match sources
may required. Credentials are stored in the operating system's secure storage or
keychain.""";
