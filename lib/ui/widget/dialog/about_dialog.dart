/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */


import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/data/help/about.dart';
import 'package:shooting_sports_analyst/html_or/html_or.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/help/help_renderer.dart';
import 'package:shooting_sports_analyst/version.dart';

void showAbout(BuildContext context, Size screenSize) {
  showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
            title: Text("About"),
            content: SizedBox(
              width: screenSize.width * 0.5,
              child: HelpRenderer(topic: helpAbout, onLinkTapped: (url) {
                HtmlOr.openLink(url);
              }),
            )
        );
      }
  );
}

// https://practiscore.com/support