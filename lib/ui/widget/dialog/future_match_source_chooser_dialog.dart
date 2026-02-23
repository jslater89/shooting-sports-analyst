/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/config/config.dart';
import 'package:shooting_sports_analyst/data/source/prematch/registration.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/match.dart';
import 'package:shooting_sports_analyst/ui/widget/future_match_source_chooser.dart';

class FutureMatchSourceChooserDialog extends StatelessWidget {
  const FutureMatchSourceChooserDialog({
    Key? key,
    this.hintText,
    required this.sources,
    this.title,
    this.descriptionText,
    this.initialSearch,
    this.onMatchDownloaded,
  }) : super(key: key);

  /// The title for the URL entry dialog.
  final String? title;
  /// The description text to show in the URL dialog, above the entry dialog.
  final String? descriptionText;
  /// The hint text to show in the URL dialog.
  final String? hintText;
  /// The list of future match sources to allow.
  final List<FutureMatchSource> sources;
  /// Initial search text.
  final String? initialSearch;
  /// Callback for when a match is downloaded in the background rather than selected for
  /// immediate viewing.
  final void Function(FutureMatch)? onMatchDownloaded;

  @override
  Widget build(BuildContext context) {
    var scaleFactor = ChangeNotifierConfigLoader().uiConfig.uiScaleFactor;
    return AlertDialog(
      title: Text(title ?? "Find a future match"),
      content: SizedBox(
        width: 800 * scaleFactor,
        height: 500 * scaleFactor,
        child: FutureMatchSourceChooser(
          sources: sources,
          initialSearch: initialSearch,
          onMatchDownloaded: onMatchDownloaded,
          onMatchSelected: (match) {
            Navigator.of(context).pop(match);
          },
        ),
      ),
      actions: [
        TextButton(
          child: Text("CANCEL"),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  static Future<(FutureMatchSource, FutureMatch)?> show(
    BuildContext context,
    List<FutureMatchSource> sources, {
    String? title,
    String? descriptionText,
    String? hintText,
    String? initialSearch,
    void Function(FutureMatch)? onMatchDownloaded,
  }) {
    return showDialog<(FutureMatchSource, FutureMatch)>(
      context: context,
      builder: (context) => FutureMatchSourceChooserDialog(
        sources: sources,
        title: title,
        descriptionText: descriptionText,
        hintText: hintText,
        initialSearch: initialSearch,
        onMatchDownloaded: onMatchDownloaded,
      ),
    );
  }
}
