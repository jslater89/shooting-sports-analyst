/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/help/help_registry.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/help/help_view.dart';
import 'package:shooting_sports_analyst/data/help/about_help.dart';
class HelpDialog extends StatelessWidget {
  final String initialTopic;
  final String title;

  const HelpDialog({super.key, required this.initialTopic, this.title = "Help"});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      content: HelpView(startingTopic: initialTopic),
    );
  }

  static Future<void> show(BuildContext context, {String initialTopic = aboutHelpId}) {
    if(kDebugMode) {
      HelpTopicRegistry().reload();
    }
    return showDialog(
      context: context,
      builder: (context) => HelpDialog(initialTopic: initialTopic),
    );
  }
}

class HelpButton extends StatelessWidget {
  final String helpTopicId;

  const HelpButton({super.key, required this.helpTopicId});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () => HelpDialog.show(context, initialTopic: helpTopicId),
      icon: const Icon(Icons.help_outline),
    );
  }
}