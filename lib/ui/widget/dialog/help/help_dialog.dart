import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/help/help_registry.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/help/help_view.dart';
import 'package:shooting_sports_analyst/data/help/about.dart';
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
      HelpTopicRegistry().initialize();
    }
    return showDialog(
      context: context,
      builder: (context) => HelpDialog(initialTopic: initialTopic),
    );
  }
}
