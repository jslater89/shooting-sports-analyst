/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/config/config.dart';
import 'package:shooting_sports_analyst/data/source/source.dart';
import 'package:shooting_sports_analyst/data/source/ssa_source/ssa_server_source.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/ui/widget/match_source_chooser.dart';

class MatchSourceChooserDialog extends StatelessWidget {
  const MatchSourceChooserDialog({
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
  /// The list of match sources to allow.
  final List<MatchSource> sources;
  /// Initial search text.
  final String? initialSearch;
  /// Callback for when a match is downloaded in the background rather than selected for
  /// immediate viewing.
  final void Function(ShootingMatch)? onMatchDownloaded;

  @override
  Widget build(BuildContext context) {
    var scaleFactor = ChangeNotifierConfigLoader().uiConfig.uiScaleFactor;
    var defaultSource = sources.firstWhereOrNull((e) => e.code == SSAServerMatchSource.ssaServerCode);
    return AlertDialog(
      title: Text(title ?? "Find a match"),
      content: SizedBox(
        width: 900 * scaleFactor,
        height: 600 * scaleFactor,
        child: MatchSourceChooser(
          sources: sources,
          defaultSource: defaultSource,
          initialSearch: initialSearch,
          onMatchSelected: (result) {
            Navigator.of(context).pop(result);
          },
          onMatchDownloaded: onMatchDownloaded,
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

  static Future<(MatchSource, ShootingMatch)?> show(
    BuildContext context,
    List<MatchSource> sources, {
    String? title,
    String? descriptionText,
    String? hintText,
    String? initialSearch,
    void Function(ShootingMatch)? onMatchDownloaded,
  }) {
    return showDialog<(MatchSource, ShootingMatch)>(
      context: context,
      builder: (context) => MatchSourceChooserDialog(
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
