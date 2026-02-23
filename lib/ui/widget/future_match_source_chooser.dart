import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/extensions/application_preferences.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/match.dart';
import 'package:shooting_sports_analyst/data/source/prematch/registration.dart';
import 'package:shooting_sports_analyst/data/source/prematch/registration_ui.dart';

class FutureMatchSourceChooser extends StatefulWidget {
  const FutureMatchSourceChooser({
    super.key,
    required this.sources,
    this.initialSearch,
    required this.onMatchSelected,
    this.onMatchDownloaded,
  });

  /// The list of future match sources to allow.
  final List<FutureMatchSource> sources;
  /// Initial search text.
  final String? initialSearch;
  /// Callback for when a match is downloaded in the background rather than selected for
  /// immediate viewing.
  final void Function(FutureMatch)? onMatchDownloaded;
  /// Callback for when a match is selected for immediate viewing.
  final void Function(FutureMatch) onMatchSelected;

  @override
  State<FutureMatchSourceChooser> createState() => _FutureMatchSourceChooserState();
}

class _FutureMatchSourceChooserState extends State<FutureMatchSourceChooser> {
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
    return Column(
      mainAxisSize: MainAxisSize.max,
      children: [
        Text("Select a match source", style: Theme.of(context).textTheme.labelSmall),
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
              widget.onMatchSelected(match);
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
    );
  }
}