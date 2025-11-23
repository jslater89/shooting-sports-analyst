/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shooting_sports_analyst/closed_sources/ps_search/ui/match_search_controls.dart';
import 'package:shooting_sports_analyst/closed_sources/ps_search/ui/match_search_results.dart';
import 'package:shooting_sports_analyst/closed_sources/ps_search/ui/search_model.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/source/match_source_error.dart';
import 'package:shooting_sports_analyst/data/source/practiscore_report.dart';
import 'package:shooting_sports_analyst/data/source/prematch/search.dart';
import 'package:shooting_sports_analyst/data/source/source.dart';
import 'package:shooting_sports_analyst/data/source/source_ui.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';

class PractiscoreReportUI extends SourceUI {
  @override
  Widget getDownloadMatchUIFor({
    required MatchSource source,
    required void Function(ShootingMatch) onMatchSelected,
    void Function(ShootingMatch)? onMatchDownloaded,
    required void Function(MatchSourceError) onError,
    String? initialSearch,
  }) {
    source as PractiscoreHitFactorReportParser;
    return Builder(builder: (context) {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<SearchModel>(create: (context) => SearchModel(initialSearch: initialSearch)),
          Provider<MatchSource>.value(value: source),
          Provider<SearchSource>.value(value: source.searchSource),
        ],
        builder: (context, child) => Column(
          children: [
            MatchSearchControls(initialSearch: initialSearch, sports: [source.sport]),
            Divider(),
            Expanded(child: MatchSearchResults(
              onMatchSelected: (searchHit) async {
                var matchResult = await source.getMatchFromId(searchHit.sourceIdsForDownload.first, sport: source.sport);
                if(matchResult.isErr()) {
                  onError(matchResult.unwrapErr());
                }
                else {
                  onMatchSelected(matchResult.unwrap());
                }
              },
              onMatchDownloadRequested: (searchHit) async {
                if(onMatchDownloaded != null) {
                  var matchResult = await source.getMatchFromId(searchHit.sourceIdsForDownload.first, sport: source.sport);
                  if(matchResult.isErr()) {
                    onError(matchResult.unwrapErr());
                  }
                  else {
                    var res = await AnalystDatabase().saveMatch(matchResult.unwrap());
                    if(res.isErr()) {
                      onError(MatchSourceError.databaseError);
                    }
                    else {
                      var hydratedMatch = res.unwrap().hydrate();
                      if(hydratedMatch.isErr()) {
                        onError(MatchSourceError.databaseError);
                      }
                      else {
                        onMatchDownloaded(hydratedMatch.unwrap());
                      }
                    }
                  }
                }
              },
              onError: (error) {
                onError(error);
              },
            )),
          ],
        )
      );
    });
  }
}
