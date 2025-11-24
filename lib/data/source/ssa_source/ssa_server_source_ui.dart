/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "package:flutter/material.dart";
import "package:provider/provider.dart";
import "package:shooting_sports_analyst/data/database/analyst_database.dart";
import "package:shooting_sports_analyst/data/source/match_source_error.dart";
import "package:shooting_sports_analyst/data/source/source.dart";
import "package:shooting_sports_analyst/data/source/source_ui.dart";
import "package:shooting_sports_analyst/data/source/ssa_source/ssa_server_source.dart";
import "package:shooting_sports_analyst/data/sport/match/match.dart";
import "package:shooting_sports_analyst/logger.dart";
import "package:shooting_sports_analyst/util.dart";

var _log = SSALogger("SSAServerSourceUI");

class SSAServerSourceUI extends SourceUI {
  @override
  Widget getDownloadMatchUIFor({
    required MatchSource source,
    required void Function(ShootingMatch) onMatchSelected,
    void Function(ShootingMatch)? onMatchDownloaded,
    required void Function(MatchSourceError) onError,
    String? initialSearch,
  }) {
    source as SSAServerMatchSource;
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SSASearchModel>(create: (context) => SSASearchModel(initialSearch: initialSearch)),
        Provider<MatchSource>.value(value: source),
      ],
      builder: (context, child) => Column(
        children: [
          SSASearchControls(initialSearch: initialSearch),
          Divider(),
          Expanded(
            child: SSASearchResults(
              source: source,
              onMatchSelected: (result) async {
                var matchResult = await source.getMatchFromId(result.matchId);
                if (matchResult.isErr()) {
                  onError(matchResult.unwrapErr());
                } else {
                  onMatchSelected(matchResult.unwrap());
                }
              },
              onMatchDownloadRequested: (result) async {
                if (onMatchDownloaded != null) {
                  var matchResult = await source.getMatchFromId(result.matchId);
                  if (matchResult.isErr()) {
                    onError(matchResult.unwrapErr());
                  } else {
                    var res = await AnalystDatabase().saveMatch(matchResult.unwrap());
                    if (res.isErr()) {
                      onError(MatchSourceError.databaseError);
                    } else {
                      var hydratedMatch = res.unwrap().hydrate();
                      if (hydratedMatch.isErr()) {
                        onError(MatchSourceError.databaseError);
                      } else {
                        onMatchDownloaded(hydratedMatch.unwrap());
                      }
                    }
                  }
                }
              },
              onError: (error) {
                onError(error);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class SSASearchModel extends ChangeNotifier {
  SSASearchModel({String? initialSearch}) {
    _search = initialSearch ?? "";
  }

  String _search = "";
  String get search => _search;
  set search(String search) {
    _search = search;
    notifyListeners();
  }
}

class SSASearchControls extends StatefulWidget {
  const SSASearchControls({super.key, this.initialSearch});

  final String? initialSearch;

  @override
  State<SSASearchControls> createState() => _SSASearchControlsState();
}

class _SSASearchControlsState extends State<SSASearchControls> {
  TextEditingController controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    controller.text = widget.initialSearch ?? "";
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var model = Provider.of<SSASearchModel>(context);

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: TextField(
        controller: controller,
        onSubmitted: (value) {
          model.search = value;
        },
        decoration: InputDecoration(
          label: Text("Search"),
          suffixIcon: IconButton(
            color: Theme.of(context).buttonTheme.colorScheme?.primary,
            icon: Icon(Icons.search),
            onPressed: () {
              model.search = controller.text;
            },
          ),
        ),
      ),
    );
  }
}

enum DownloadState {
  idle,
  downloading,
  success,
  error,
}

class SSASearchResults extends StatefulWidget {
  const SSASearchResults({
    super.key,
    required this.source,
    required this.onMatchSelected,
    this.onMatchDownloadRequested,
    required this.onError,
  });

  final SSAServerMatchSource source;
  final void Function(MatchSearchResult<ServerMatchType>) onMatchSelected;
  final void Function(MatchSearchResult<ServerMatchType>)? onMatchDownloadRequested;
  final void Function(MatchSourceError) onError;

  @override
  State<SSASearchResults> createState() => _SSASearchResultsState();
}

class _SSASearchResultsState extends State<SSASearchResults> {
  late SSASearchModel model;
  List<MatchSearchResult<ServerMatchType>> results = [];
  Map<String, DownloadState> downloadStates = {};
  String latestSearch = "";

  @override
  void initState() {
    super.initState();
    try {
      model = Provider.of<SSASearchModel>(context, listen: false);
      model.addListener(_onModelChanged);

      // Handle initial search
      if (model.search != latestSearch) {
        _search();
      }
    }
    catch(e) {
      _log.e("Error initializing SSASearchResults", error: e);
      // provider no longer exists; build during source switch
    }
  }

  @override
  void dispose() {
    model.removeListener(_onModelChanged);
    super.dispose();
  }

  void _onModelChanged() {
    _search();
  }

  Future<void> _search() async {
    if (model.search == latestSearch) return;

    var searchTerm = model.search;
    latestSearch = searchTerm;

    try {
      if(searchTerm.isEmpty) {
        setState(() {
          results = [];
        });
        return;
      }

      var searchResult = await widget.source.findMatches(searchTerm);
      if (searchTerm != latestSearch) {
        // Another search came in before this one returned
        return;
      }

      if (searchResult.isOk()) {
        setState(() {
          results = searchResult.unwrap();
        });
      }
      else {
        var err = searchResult.unwrapErr();
        widget.onError(err);
      }
    } catch (e) {
      // Probably a canceled request
      widget.onError(GeneralError(StringError("Search error: $e")));
    }
  }

  Future<void> _downloadMatch(MatchSearchResult<ServerMatchType> result) async {
    if (widget.onMatchDownloadRequested == null) return;

    setState(() {
      downloadStates[result.matchId] = DownloadState.downloading;
    });

    try {
      var matchResult = await widget.source.getMatchFromId(result.matchId);
      if (matchResult.isErr()) {
        setState(() {
          downloadStates[result.matchId] = DownloadState.error;
        });
        widget.onError(matchResult.unwrapErr());
        return;
      }

      var res = await AnalystDatabase().saveMatch(matchResult.unwrap());
      if (res.isErr()) {
        setState(() {
          downloadStates[result.matchId] = DownloadState.error;
        });
        widget.onError(MatchSourceError.databaseError);
        return;
      }

      var hydratedMatch = res.unwrap().hydrate();
      if (hydratedMatch.isErr()) {
        setState(() {
          downloadStates[result.matchId] = DownloadState.error;
        });
        widget.onError(MatchSourceError.databaseError);
        return;
      }

      setState(() {
        downloadStates[result.matchId] = DownloadState.success;
      });

      widget.onMatchDownloadRequested!(result);
    } catch (e) {
      setState(() {
        downloadStates[result.matchId] = DownloadState.error;
      });
      widget.onError(GeneralError(StringError("Download error: $e")));
    }
  }

  Widget _buildDownloadIndicator(String matchId) {
    var state = downloadStates[matchId] ?? DownloadState.idle;
    switch (state) {
      case DownloadState.idle:
        return SizedBox.shrink();
      case DownloadState.downloading:
        return SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case DownloadState.success:
        return Icon(Icons.check, color: Colors.green, size: 20);
      case DownloadState.error:
        return Icon(Icons.error, color: Colors.red, size: 20);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemBuilder: (context, i) {
        var result = results[i];
        var downloadState = downloadStates[result.matchId] ?? DownloadState.idle;
        var isDownloading = downloadState == DownloadState.downloading;

        return ListTile(
          title: Text(result.matchName),
          subtitle: Text(
            "${result.matchSubtype} - ${result.matchDate != null ? programmerYmdFormat.format(result.matchDate!) : "unknown date"}",
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDownloadIndicator(result.matchId),
              if (widget.onMatchDownloadRequested != null && !isDownloading)
                IconButton(
                  icon: Icon(Icons.download),
                  onPressed: () => _downloadMatch(result),
                  tooltip: "Download match",
                ),
            ],
          ),
          onTap: isDownloading ? null : () async {
            widget.onMatchSelected(result);
          },
        );
      },
      separatorBuilder: (context, i) => Divider(),
      itemCount: results.length,
    );
  }
}

