/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/data/source/match_source_error.dart';
import 'package:shooting_sports_analyst/data/source/search.dart';

class MatchSearchResults extends StatelessWidget {
  const MatchSearchResults({super.key, required this.onMatchSelected, required this.onMatchDownloadRequested, required this.onError});

  final void Function(SearchSourceHit) onMatchSelected;
  final void Function(SearchSourceHit) onMatchDownloadRequested;
  final void Function(MatchSourceError) onError;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text("Not available in this build."),
    );
  }
}