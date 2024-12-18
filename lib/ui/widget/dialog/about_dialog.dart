/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */


import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/html_or/html_or.dart';
import 'package:shooting_sports_analyst/version.dart';

void showAbout(BuildContext context, Size screenSize) {
  showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
            title: Text("About"),
            content: SizedBox(
              width: screenSize.width * 0.5,
              child: RichText(
                  text: TextSpan(
                      children: [
                        TextSpan(
                            style: Theme.of(context).textTheme.bodyText1,
                            text: "A Flutter desktop application for viewing, analyzing, and predicting USPSA match results. "
                                "A web application is also available for viewing results only, and can be embedded into your "
                                "match website if you want to host your own results.\n\n"
                                "Visit the repository at "
                        ),
                        TextSpan(
                            text: "https://github.com/jslater89/shooting-sports-analyst",
                            style: Theme.of(context).textTheme.bodyText1!.apply(color: Theme.of(context).colorScheme.primary),
                            recognizer: TapGestureRecognizer()..onTap = () async {
                              String url = "https://github.com/jslater89/shooting-sports-analyst";
                              HtmlOr.openLink(url);
                            }
                        ),
                        TextSpan(
                            style: Theme.of(context).textTheme.bodyText1,
                            text: " for more information.\nShooting Sports Analyst v${VersionInfo.version}\nMPL 2.0, except where noted\n\n"
                                "USPSA, IDPA, PCSL, PractiScore, and other trade names or trademarks are used solely for descriptive or "
                                "nominative purposes, and their use does not imply endorsement by their respective rights-holders, or affiliation "
                                "between them and Shooting Sports Analyst."
                        )
                      ]
                  )
              ),
            )
        );
      }
  );
}

// https://practiscore.com/support