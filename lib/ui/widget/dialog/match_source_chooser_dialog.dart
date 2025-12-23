/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/config/config.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/extensions/application_preferences.dart';
import 'package:shooting_sports_analyst/data/database/schema/preferences.dart';
import 'package:shooting_sports_analyst/data/source/source.dart';
import 'package:shooting_sports_analyst/data/source/source_ui.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';

class MatchSourceChooserDialog extends StatefulWidget {
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
  State<MatchSourceChooserDialog> createState() => _MatchSourceChooserDialogState();

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

class _MatchSourceChooserDialogState extends State<MatchSourceChooserDialog> {
  // final TextEditingController _urlController = TextEditingController();

  String? errorText;
  late MatchSource source;

  @override
  void initState() {
    super.initState();
    source = widget.sources.first;
    var lastUsedSourceCode = AnalystDatabase().getPreferencesSync().lastUsedSourceCode;
    if(lastUsedSourceCode != null) {
      var maybeSource = widget.sources.firstWhereOrNull((e) => e.code == lastUsedSourceCode);
      if(maybeSource != null) {
        source = maybeSource;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    var scaleFactor = ChangeNotifierConfigLoader().uiConfig.uiScaleFactor;
    return AlertDialog(
      title: Text(widget.title ?? "Find a match"),
      content: SizedBox(
        width: 900 * scaleFactor,
        height: 600 * scaleFactor,
        child: Column(
          mainAxisSize: MainAxisSize.max,
          children: [
            DropdownButton(
              items: widget.sources.map((e) => DropdownMenuItem(
                child: Text(e.name),
                value: e,
              )).toList(),
              onChanged: (s) {
                if(s != null) {
                  var prefs = AnalystDatabase().getPreferencesSync();
                  prefs.lastUsedSourceCode = s.code;
                  AnalystDatabase().savePreferencesSync(prefs);
                  setState(() {
                    source = s;
                  });
                }
              },
              value: source,
            ),
            Divider(),
            Expanded(child:
              SourceUI.forSource(source).getDownloadMatchUIFor(
                source: source,
                onMatchSelected: (match) {
                  submit(match);
                },
                onMatchDownloaded: widget.onMatchDownloaded,
                onError: (error) {
                  showDialog(context: context, builder: (context) => AlertDialog(
                    title: Text("Match source error"),
                    content: Text(error.message),
                  ));
                },
                initialSearch: widget.initialSearch,
              )
            ),
          ],
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

  void submit(ShootingMatch match) {
    Navigator.of(context).pop((source, match));
  }
}
