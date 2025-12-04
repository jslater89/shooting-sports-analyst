/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/extensions/match_prep.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/match.dart';
import 'package:shooting_sports_analyst/data/source/match_source_error.dart';
import 'package:shooting_sports_analyst/data/source/prematch/registration.dart';
import 'package:shooting_sports_analyst/data/source/prematch/registration_ui.dart';
import 'package:shooting_sports_analyst/data/source/ssa_source/ssa_auth.dart';
import 'package:shooting_sports_analyst/data/source/ssa_source/ssa_server_registration_source.dart';
import 'package:shooting_sports_analyst/data/source/ssa_source/ssa_server_source_ui.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/future_match_database_chooser_dialog.dart';
import 'package:shooting_sports_analyst/util.dart';

var _log = SSALogger("SSAServerFutureMatchSourceUI");

class SSAServerFutureMatchSourceUI extends FutureMatchSourceUI {
  @override
  Widget getDownloadMatchUIFor({
    required FutureMatchSource source,
    required void Function(FutureMatch) onMatchSelected,
    void Function(FutureMatch)? onMatchDownloaded,
    required void Function(MatchSourceError) onError,
    String? initialSearch,
  }) {
    source as SSAServerFutureMatchSource;
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SSASearchModel>(create: (context) => SSASearchModel(initialSearch: initialSearch)),
        Provider<FutureMatchSource>.value(value: source),
      ],
      builder: (context, child) {
        var canUpload = source.canUpload;
        var validAuth = isCurrentlyAuthenticated;
        return StatefulBuilder(
          builder: (context, setState) {
            return Column(
              children: [
                Row(
                  children: [
                    Expanded(child: SSASearchControls(initialSearch: initialSearch)),
                    if(canUpload) IconButton(
                      icon: Icon(Icons.upload),
                      onPressed: () async {
                        var matches = await FutureMatchDatabaseChooserDialog.showMultiple(
                          context: context,
                          showIds: true,
                        );
                        if(matches == null) return;
                        for(var match in matches) {
                          var result = await source.uploadMatch(match);
                          if(result != null) {
                            onError(result);
                          }
                        }
                      },
                    ),
                    if(!validAuth) IconButton(
                      icon: Icon(Icons.refresh),
                      onPressed: () async {
                        await refreshAuth();
                        setState(() {
                          canUpload = source.canUpload;
                          validAuth = isCurrentlyAuthenticated;
                        });
                      },
                    ),
                  ],
                ),
                Divider(),
                Expanded(
                  child: SSAFutureMatchSearchResults(
                    source: source,
                    onMatchSelected: (result) async {
                      var matchResult = await source.getMatchById(result.matchId);
                      if (matchResult.isErr()) {
                        onError(matchResult.unwrapErr());
                      }
                      else {
                        onMatchSelected(matchResult.unwrap());
                      }
                    },
                    onMatchDownloadRequested: onMatchDownloaded == null ? null : (result) async {
                      var matchResult = await source.getMatchById(result.matchId);
                      if (matchResult.isErr()) {
                        onError(matchResult.unwrapErr());
                      }
                      else {
                        var res = await AnalystDatabase().saveFutureMatch(matchResult.unwrap());
                        if (res.isErr()) {
                          onError(MatchSourceError.databaseError);
                        }
                        else {
                          onMatchDownloaded(matchResult.unwrap());
                        }
                      }
                    },
                    onError: onError,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class SSAFutureMatchSearchResults extends StatefulWidget {
  const SSAFutureMatchSearchResults({
    super.key,
    required this.source,
    required this.onMatchSelected,
    this.onMatchDownloadRequested,
    required this.onError,
  });

  final SSAServerFutureMatchSource source;
  final void Function(FutureMatch) onMatchSelected;
  final void Function(FutureMatchSearchHit)? onMatchDownloadRequested;
  final void Function(MatchSourceError) onError;

  @override
  State<SSAFutureMatchSearchResults> createState() => _SSAFutureMatchSearchResultsState();
}

class _SSAFutureMatchSearchResultsState extends State<SSAFutureMatchSearchResults> {
  late SSASearchModel model;
  List<FutureMatchSearchHit> results = [];
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
    if(!model.searching) return;
    _search();
  }

  Future<void> _search() async {
    if (model.search == latestSearch) {
      model.stopSearch();
      return;
    }

    var searchTerm = model.search;
    latestSearch = searchTerm;

    try {
      if(searchTerm.isEmpty) {
        setState(() {
          results = [];
        });
        model.stopSearch();
        return;
      }

      var searchResult = await widget.source.searchByName(searchTerm);
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
    }
    catch (e) {
      // Probably a canceled request
      widget.onError(GeneralError(StringError("Search error: $e")));
    }
    finally {
      model.stopSearch();
    }
  }

  Future<void> _downloadMatch(FutureMatchSearchHit result) async {
    if (widget.onMatchDownloadRequested == null) return;

    setState(() {
      downloadStates[result.matchId] = DownloadState.downloading;
    });

    try {
      var matchResult = await widget.source.getMatchById(result.matchId);
      if (matchResult.isErr()) {
        setState(() {
          downloadStates[result.matchId] = DownloadState.error;
        });
        widget.onError(matchResult.unwrapErr());
        return;
      }

      var res = await AnalystDatabase().saveFutureMatch(matchResult.unwrap());
      if (res.isErr()) {
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
            "${result.sportName} - ${programmerYmdFormat.format(result.matchStartDate)}",
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
            var matchResult = await widget.source.getMatchById(result.matchId);
            if (matchResult.isErr()) {
              widget.onError(matchResult.unwrapErr());
            }
            else {
              widget.onMatchSelected(matchResult.unwrap());
            }
          },
        );
      },
      separatorBuilder: (context, i) => Divider(),
      itemCount: results.length,
    );
  }
}

