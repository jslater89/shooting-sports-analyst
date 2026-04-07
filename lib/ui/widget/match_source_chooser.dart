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
import 'package:shooting_sports_analyst/data/source/source.dart';
import 'package:shooting_sports_analyst/data/source/source_ui.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';

class MatchSourceChooser extends StatefulWidget {
  const MatchSourceChooser({
    super.key,
    required this.sources,
    this.defaultSource,
    this.initialSearch,
    required this.onMatchSelected,
    this.onMatchDownloaded,
  });

  /// The list of match sources to allow.
  final List<MatchSource> sources;
  /// The default source to select, if none has been selected before.
  final MatchSource? defaultSource;
  /// Initial search text.
  final String? initialSearch;

  /// Callback for when a match is selected for immediate viewing.
  final void Function((MatchSource, ShootingMatch)) onMatchSelected;
  /// Callback for when a match is downloaded in the background rather than selected for
  /// immediate viewing.
  final void Function(ShootingMatch)? onMatchDownloaded;

  @override
  State<MatchSourceChooser> createState() => _MatchSourceChooserState();
}

class _MatchSourceChooserState extends State<MatchSourceChooser> {
  String? errorText;
  late MatchSource source;

  @override
  void initState() {
    super.initState();
    source = widget.defaultSource ?? widget.sources.first;
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
    return Column(
      mainAxisSize: MainAxisSize.max,
      children: [
        Text("Select a match source", style: Theme.of(context).textTheme.labelSmall),
        DropdownButton<MatchSource>(
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
        if(source.degraded) SourceDegradedWarning(source.degradedReason),
        Divider(),
        Expanded(child:
          SourceUI.forSource(source).getDownloadMatchUIFor(
            source: source,
            onMatchSelected: (match) {
              widget.onMatchSelected((source, match));
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
    );
  }
}

class SourceDegradedWarning extends StatelessWidget {
  const SourceDegradedWarning(this.reason, {super.key});

  final String? reason;

  @override
  Widget build(BuildContext context) {
    final uiScaleFactor = ChangeNotifierConfigLoader().uiConfig.uiScaleFactor;
    return Padding(
      padding: EdgeInsets.all(8 * uiScaleFactor),
      child: Container(
        padding: EdgeInsets.all(8 * uiScaleFactor),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.error,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          spacing: 8,
          children: [
            Icon(Icons.warning, color: Theme.of(context).colorScheme.onError),
            Expanded(
              child: Text(reason ?? "This source may not function correctly.",
                style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: Theme.of(context).colorScheme.onError),
                softWrap: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}