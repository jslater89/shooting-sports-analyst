/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/config/config.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/match.dart';
import 'package:shooting_sports_analyst/data/help/entries/match_source_chooser_help.dart';
import 'package:shooting_sports_analyst/data/source/prematch/registration.dart';
import 'package:shooting_sports_analyst/data/source/source.dart';
import 'package:shooting_sports_analyst/data/source/ssa_source/ssa_server_source.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/help/help_dialog.dart';
import 'package:shooting_sports_analyst/ui/widget/future_match_source_chooser.dart';
import 'package:shooting_sports_analyst/ui/widget/keepalive_tab.dart';
import 'package:shooting_sports_analyst/ui/widget/match_source_chooser.dart';

class MatchOrFutureMatchSourceChooserDialog extends StatefulWidget {
  const MatchOrFutureMatchSourceChooserDialog({
    super.key,
    required this.matchSources,
    required this.futureMatchSources,
    this.title,
    this.initialSearch,
    this.onMatchDownloaded,
    this.onFutureMatchDownloaded,
  });

  final List<MatchSource> matchSources;
  final List<FutureMatchSource> futureMatchSources;

  /// The title for the dialog.
  final String? title;
  /// The initial search text.
  final String? initialSearch;

  /// Callback for when a match is downloaded in the background rather than selected for
  /// immediate viewing.
  final void Function(ShootingMatch)? onMatchDownloaded;
  /// Callback for when a future match is downloaded in the background rather than selected for
  /// immediate viewing.
  final void Function(FutureMatch)? onFutureMatchDownloaded;

  @override
  State<MatchOrFutureMatchSourceChooserDialog> createState() => _MatchOrFutureMatchSourceChooserDialogState();

  static Future<MatchOrFutureMatch?> show({
    required BuildContext context,
    required List<MatchSource> matchSources,
    required List<FutureMatchSource> futureMatchSources,
    String? title,
    String? initialSearch,
    void Function(ShootingMatch)? onMatchDownloaded,
    void Function(FutureMatch)? onFutureMatchDownloaded,
  }) {
    return showDialog<MatchOrFutureMatch>(context: context, builder: (context) => MatchOrFutureMatchSourceChooserDialog(
      matchSources: matchSources,
      futureMatchSources: futureMatchSources,
      title: title,
      initialSearch: initialSearch,
      onMatchDownloaded: onMatchDownloaded,
      onFutureMatchDownloaded: onFutureMatchDownloaded,
    ));
  }
}

class _MatchOrFutureMatchSourceChooserDialogState extends State<MatchOrFutureMatchSourceChooserDialog> with TickerProviderStateMixin {
  late TabController _tabController;

  MatchSource? _defaualtMatchSource;
  late String _helpText;

  @override
  void initState() {
    super.initState();
    _defaualtMatchSource = widget.matchSources.firstWhereOrNull((e) => e.code == SSAServerMatchSource.ssaServerCode);
    _tabController = TabController(length: 2, vsync: this);
    _helpText = _getHelpText();
    _tabController.addListener(() {
      setState(() {
        _helpText = _getHelpText();
      });
    });
  }

  String _getHelpText() {
    return _tabController.index == 0
      ? "Selecting a match will open it for viewing."
      : "Selecting a future match will download it and save it for use in creating match preps.";
  }


  @override
  Widget build(BuildContext context) {
    var scaleFactor = ChangeNotifierConfigLoader().uiConfig.uiScaleFactor;
    return AlertDialog(
      title: Row(
        children: [
          Expanded(child: Text(widget.title ?? "Find a match or future match")),
          HelpButton(helpTopicId: matchSourceChooserHelpId),
        ],
      ),
      content: SizedBox(
        width: 900 * scaleFactor,
        height: 800 * scaleFactor,
        child: Column(
          children: [
            Text(_helpText),
            SizedBox(
              height: 50 * scaleFactor,
              child: TabBar(
                controller: _tabController,
                tabs: [
                  Tab(text: "Match"),
                  Tab(text: "Future Match"),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  KeepAliveTab(
                    child: Padding(
                      padding: EdgeInsets.only(top: 8 * scaleFactor),
                      child: MatchSourceChooser(
                        sources: widget.matchSources,
                        defaultSource: _defaualtMatchSource,
                        initialSearch: widget.initialSearch,
                        onMatchSelected: (result) {
                          Navigator.of(context).pop(MatchOrFutureMatch.match(result.$1, result.$2));
                        },
                        onMatchDownloaded: widget.onMatchDownloaded,
                      ),
                    ),
                  ),
                  KeepAliveTab(
                    child: Padding(
                      padding: EdgeInsets.only(top: 8 * scaleFactor),
                      child: FutureMatchSourceChooser(
                        sources: widget.futureMatchSources,
                        initialSearch: widget.initialSearch,
                        onMatchDownloaded: widget.onFutureMatchDownloaded,
                        onMatchSelected: (match) {
                          Navigator.of(context).pop(MatchOrFutureMatch.futureMatch(match));
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MatchOrFutureMatch {
  final MatchSource? _matchSource;
  final ShootingMatch? _match;

  final FutureMatch? _futureMatch;

  MatchOrFutureMatch.futureMatch(this._futureMatch) : _matchSource = null, _match = null;
  MatchOrFutureMatch.match(this._matchSource, this._match) : _futureMatch = null;

  bool isFutureMatch() => _futureMatch != null;
  bool isMatch() => _match != null;

  FutureMatch unwrapFutureMatch() => _futureMatch!;
  (MatchSource, ShootingMatch) unwrapMatch() => (_matchSource!, _match!);
}