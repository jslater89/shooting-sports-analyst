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
import 'package:shooting_sports_analyst/data/source/prematch/registration.dart';
import 'package:shooting_sports_analyst/data/source/prematch/registration_ui.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/match.dart';

class FutureMatchSourceChooserDialog extends StatefulWidget {
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
  State<FutureMatchSourceChooserDialog> createState() => _FutureMatchSourceChooserDialogState();

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

class _FutureMatchSourceChooserDialogState extends State<FutureMatchSourceChooserDialog> {
  String? errorText;
  late FutureMatchSource source;

  @override
  void initState() {
    super.initState();
    source = widget.sources.first;
    var lastUsedSourceCode = AnalystDatabase().getPreferencesSync().lastUsedFutureMatchSourceCode;
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
      title: Text(widget.title ?? "Find a future match"),
      content: SizedBox(
        width: 800 * scaleFactor,
        height: 500 * scaleFactor,
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
                  prefs.lastUsedFutureMatchSourceCode = s.code;
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
              FutureMatchSourceUI.forSource(source).getDownloadMatchUIFor(
                source: source,
                onMatchSelected: (match) {
                  submit(match);
                },
                onMatchDownloaded: widget.onMatchDownloaded,
                onError: (error) {
                  showDialog(context: context, builder: (context) => AlertDialog(
                    title: Text("Future match source error"),
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

  void submit(FutureMatch match) {
    Navigator.of(context).pop((source, match));
  }
}

