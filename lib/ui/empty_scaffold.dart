/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/data/help/entries/about_help.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/help/help_dialog.dart';
import 'package:shooting_sports_analyst/ui/workspace/workspace_label_reporter.dart';

/// The normal scaffold for Analyst, with a title, list of actions, progress indicator, and body.
class EmptyScaffold extends StatelessWidget {
  final Widget? child;
  final String? title;
  final bool? operationInProgress;
  final String? helpTopicId;
  final List<Widget> actions;

  /// When set, publishes this section (and optional [workspaceDetail]) to the
  /// enclosing workspace tab while this route is current.
  final String? workspaceSection;
  final String? workspaceDetail;

  const EmptyScaffold({
    Key? key,
    this.child,
    this.operationInProgress = false,
    this.title,
    this.actions = const [],
    this.helpTopicId,
    this.workspaceSection,
    this.workspaceDetail,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // final uiScaleFactor = ChangeNotifierConfigLoader().uiConfig.uiScaleFactor;
    // var size = MediaQuery.of(context).size;
    final primaryColor = Theme.of(context).primaryColor;
    final backgroundColor = Theme.of(context).colorScheme.surface;
    var animation = operationInProgress! ?
    AlwaysStoppedAnimation<Color>(backgroundColor) : AlwaysStoppedAnimation<Color>(primaryColor);

    // TODO: need an AnalystScaffold wrapper that handles this for us.
    // We don't always use a bare EmptyScaffold, so we need a plainer wrapper we can
    // put in all the places we have plain Scaffolds.

    Widget scaffold = Scaffold(
      appBar: AppBar(
        // toolbarHeight: toolbarHeight,
        title: Text(title ?? "Shooting Sports Analyst"),
        centerTitle: true,
        actions: [
          ...actions,
          HelpButton(helpTopicId: helpTopicId ?? aboutHelpId),
        ],
        bottom: operationInProgress! ? PreferredSize(
          preferredSize: Size(double.infinity, 5),
          child: LinearProgressIndicator(value: null, backgroundColor: primaryColor, valueColor: animation),
        ) : null,
      ),
      body: Builder(
        builder: (context) {
          return child!;
        },
      ),
    );

    final section = workspaceSection;
    if(section != null) {
      scaffold = WorkspaceLabelReporter(
        section: section,
        detail: workspaceDetail,
        child: scaffold,
      );
    }

    return scaffold;
  }

}
