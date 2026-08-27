/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "package:flutter/material.dart";
import "package:provider/provider.dart";
import "package:shooting_sports_analyst/config/config.dart";
import "package:shooting_sports_analyst/data/database/analyst_database.dart";
import "package:shooting_sports_analyst/data/source/hitfacto_rs/hitfacto_rs_fetch_options.dart";
import "package:shooting_sports_analyst/data/source/hitfacto_rs/hitfacto_rs_match_type.dart";
import "package:shooting_sports_analyst/data/source/hitfacto_rs/hitfacto_rs_search_model.dart";
import "package:shooting_sports_analyst/data/source/hitfacto_rs/hitfacto_rs_source.dart";
import "package:shooting_sports_analyst/data/source/match_source_error.dart";
import "package:shooting_sports_analyst/data/source/source.dart";
import "package:shooting_sports_analyst/data/source/source_ui.dart";
import "package:shooting_sports_analyst/data/sport/match/match.dart";
import "package:shooting_sports_analyst/logger.dart";
import "package:shooting_sports_analyst/ui/widget/dialog/loading_dialog.dart";
import "package:shooting_sports_analyst/util.dart";

final _log = SSALogger("HitfactoRsUI");

class HitfactoRsUI extends SourceUI {
  @override
  Widget getDownloadMatchUIFor({
    required MatchSource source,
    required void Function(ShootingMatch) onMatchSelected,
    void Function(ShootingMatch)? onMatchDownloaded,
    required void Function(MatchSourceError) onError,
    String? initialSearch,
  }) {
    return Provider<MatchSource>.value(
      value: source,
      child: ChangeNotifierProvider<HitfactoRsSearchModel>(
        create: (context) =>
            HitfactoRsSearchModel(initialSearch: initialSearch),
        builder: (context, child) => Column(
          mainAxisSize: MainAxisSize.max,
          children: [
            Text(
              "Search Hitfacto.rs (USPSA). Optional API key for higher rate limits — use the key icon "
              "(saved to config.toml). Unauthenticated requests use default limits.",
            ),
            HitfactoRsMatchSearchControls(initialSearch: initialSearch),
            Divider(),
            Expanded(
              child: HitfactoRsMatchSearchResults(
                onMatchSelected: onMatchSelected,
                onMatchDownloaded: onMatchDownloaded,
                onError: onError,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HitfactoRsMatchSearchControls extends StatefulWidget {
  const HitfactoRsMatchSearchControls({super.key, this.initialSearch});

  final String? initialSearch;

  @override
  State<HitfactoRsMatchSearchControls> createState() =>
      _HitfactoRsMatchSearchControlsState();
}

class _HitfactoRsMatchSearchControlsState
    extends State<HitfactoRsMatchSearchControls> {
  late TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.initialSearch ?? "");
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _promptHitfactoApiKey(BuildContext context) async {
    final loader = ChangeNotifierConfigLoader();
    final cfg = loader.config.copy();
    final controller = TextEditingController(text: cfg.hitfactoRsApiKey);
    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (ctx) {
        return AlertDialog(
          title: Text("Hitfacto.rs API Key"),
          content: TextField(
            controller: controller,
            obscureText: true,
            autofocus: true,
            decoration: InputDecoration(
              hintText: "Optional — empty for unauthenticated access",
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text("Cancel"),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text("Save"),
            ),
          ],
        );
      },
    );
    try {
      if (ok == true) {
        cfg.hitfactoRsApiKey = controller.text.trim();
        await loader.setConfig(cfg);
      }
    } finally {
      controller.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final model = Provider.of<HitfactoRsSearchModel>(context);

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              onSubmitted: (value) {
                model.search = value;
              },
              decoration: InputDecoration(
                label: Text("Search"),
                suffixIcon: IconButton(
                  color: Theme.of(context).buttonTheme.colorScheme?.primary,
                  icon: Icon(Icons.search),
                  onPressed: () {
                    model.search = _searchController.text;
                  },
                ),
              ),
            ),
          ),
          SizedBox(width: 8),
          Tooltip(
            message: "Ignore unknown divisions",
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Checkbox(
                  value: model.ignoreUnknownDivisions,
                  onChanged: (v) {
                    model.ignoreUnknownDivisions = v ?? false;
                  },
                ),
                Text(
                  "Ignore unknown divisions",
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          ListenableBuilder(
            listenable: ChangeNotifierConfigLoader(),
            builder: (context, _) {
              final hasKey = ChangeNotifierConfigLoader()
                  .config
                  .hitfactoRsApiKey
                  .isNotEmpty;
              return IconButton(
                tooltip: hasKey
                    ? "Edit Hitfacto.rs API key (config.toml)"
                    : "Set Hitfacto.rs API key (config.toml)",
                icon: Icon(
                  Icons.key,
                  color: hasKey
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).disabledColor,
                ),
                onPressed: () => _promptHitfactoApiKey(context),
              );
            },
          ),
        ],
      ),
    );
  }
}

class HitfactoRsMatchSearchResults extends StatefulWidget {
  const HitfactoRsMatchSearchResults({
    super.key,
    required this.onMatchSelected,
    this.onMatchDownloaded,
    required this.onError,
  });

  final void Function(ShootingMatch) onMatchSelected;
  final void Function(ShootingMatch)? onMatchDownloaded;
  final void Function(MatchSourceError) onError;

  @override
  State<HitfactoRsMatchSearchResults> createState() =>
      _HitfactoRsMatchSearchResultsState();
}

class _HitfactoRsMatchSearchResultsState
    extends State<HitfactoRsMatchSearchResults> {
  late HitfactoRsSearchModel model;
  late HitfactoRsMatchSource source;

  @override
  void initState() {
    super.initState();
    model = Provider.of<HitfactoRsSearchModel>(context, listen: false);
    source =
        Provider.of<MatchSource>(context, listen: false)
            as HitfactoRsMatchSource;
    model.addListener(_onModelChanged);
    if (model.search != _latestSearch) {
      _search();
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

  String _latestSearch = "";

  Future<void> _search() async {
    final m = Provider.of<HitfactoRsSearchModel>(context, listen: false);
    if (m.search == _latestSearch) {
      return;
    }
    final searchTerm = m.search;
    _latestSearch = searchTerm;

    try {
      final searchResult = await source.findMatches(searchTerm);
      if (searchTerm != _latestSearch) {
        return;
      }
      if (searchResult.isOk()) {
        final resultList = searchResult.unwrap();
        setState(() {
          results = resultList;
        });
      } else {
        _log.e("Error searching: ${searchResult.unwrapErr()}");
      }
    } catch (e, st) {
      _log.e("Caught error searching", error: e, stackTrace: st);
    }
  }

  List<MatchSearchResult<HitfactoRsMatchType>> results = [];

  HitfactoRsMatchFetchOptions get _fetchOptions => HitfactoRsMatchFetchOptions(
    downloadScoreLogs: false,
    ignoreUnknownDivisions: model.ignoreUnknownDivisions,
    fuzzyHitFactorDivisionMatching: true,
  );

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemBuilder: (context, i) {
        final result = results[i];
        return ListTile(
          title: Text(result.matchName),
          subtitle: Text(
            "${result.matchType?.name ?? "unknown"} (${result.matchSubtype}) ${result.matchId} "
            "${result.matchDate != null ? programmerYmdFormat.format(result.matchDate!) : "unknown date"}",
          ),
          onTap: () async {
            final matchResultFuture = source.getMatchFromSearch(
              result,
              options: _fetchOptions,
            );
            final matchResult = await LoadingDialog.show(
              context: context,
              waitOn: matchResultFuture,
            );
            if (matchResult != null && matchResult.isOk()) {
              widget.onMatchSelected(matchResult.unwrap());
            } else {
              widget.onError(
                matchResult?.unwrapErr() ?? MatchSourceError.notFound,
              );
            }
          },
          onLongPress: () async {
            final matchResultFuture = source.getMatchFromSearch(
              result,
              options: _fetchOptions,
            );
            final matchResult = await LoadingDialog.show(
              title: "Saving match...",
              context: context,
              waitOn: matchResultFuture,
            );
            if (matchResult != null && matchResult.isOk()) {
              final match = matchResult.unwrap();
              final res = await AnalystDatabase().saveMatch(match);
              if (res.isErr()) {
                _log.e("Error saving match: ${res.unwrapErr()}");
              } else {
                _log.i("Saved match: ${res.unwrap()}");
                widget.onMatchDownloaded?.call(match);
              }
            }
          },
        );
      },
      separatorBuilder: (context, i) => Divider(),
      itemCount: results.length,
    );
  }
}
