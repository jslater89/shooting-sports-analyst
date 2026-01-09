/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/config/config.dart';
import 'package:shooting_sports_analyst/data/help/entries/about_help.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/help/help_dialog.dart';

/// The normal scaffold for Analyst, with a title, list of actions, progress indicator, and body.
class EmptyScaffold extends StatelessWidget {
  final Widget? child;
  final String? title;
  final bool? operationInProgress;
  final String? helpTopicId;
  final List<Widget> actions;

  const EmptyScaffold({Key? key, this.child, this.operationInProgress = false, this.title, this.actions = const [], this.helpTopicId}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final uiScaleFactor = ChangeNotifierConfigLoader().uiConfig.uiScaleFactor;
    var size = MediaQuery.of(context).size;
    final primaryColor = Theme.of(context).primaryColor;
    final backgroundColor = Theme.of(context).colorScheme.surface;
    var animation = operationInProgress! ?
    AlwaysStoppedAnimation<Color>(backgroundColor) : AlwaysStoppedAnimation<Color>(primaryColor);

    // TODO: need an AnalystScaffold wrapper that handles this for us.
    // We don't always use a bare EmptyScaffold, so we need a plainer wrapper we can
    // put in all the places we have plain Scaffolds.

    // var toolbarHeight;
    // // Grow by half the scale factor.
    // if(uiScaleFactor > 1.0) {
    //   toolbarHeight = kToolbarHeight * (1 + ((uiScaleFactor - 1) * 0.5));
    // }
    // else if(uiScaleFactor < 1.0) {
    //   // shrink by 125% of the scale factor.
    //   toolbarHeight = kToolbarHeight * (1 - ((uiScaleFactor - 1) * 1.25));
    // }
    // else {
    //   toolbarHeight = kToolbarHeight;
    // }

    return Scaffold(
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
  }

}
