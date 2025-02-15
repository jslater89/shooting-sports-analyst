/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */


import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/data/help/about_help.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/help/help_dialog.dart';

void showAbout(BuildContext context, Size screenSize) {
  HelpDialog.show(context, initialTopic: aboutHelpId);
}
