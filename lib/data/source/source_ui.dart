/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/closed_sources/psv2/psv2_source.dart';
import 'package:shooting_sports_analyst/closed_sources/psv2/psv2_ui.dart';
import 'package:shooting_sports_analyst/closed_sources/ssa_server_source/ssa_server_source.dart';
import 'package:shooting_sports_analyst/closed_sources/ssa_server_source/ssa_server_source_ui.dart';
import 'package:shooting_sports_analyst/data/source/match_source_error.dart';
import 'package:shooting_sports_analyst/data/source/practiscore_report.dart';
import 'package:shooting_sports_analyst/data/source/practiscore_report_ui.dart';
import 'package:shooting_sports_analyst/data/source/source.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';

abstract class SourceUI {
  /// Return the UI to be displayed in the 'get match' dialog.
  ///
  /// The returned UI should fit an 800px by 500px box (or allow scrolling, if taller
  /// than 500px). The enclosing UI will provide 'cancel' or 'back' functionality.
  ///
  /// Call [onMatchSelected] with a match if one is selected for immediate viewing,
  /// [onMatchDownloaded] with a match if one is selected for background download, or
  /// [onError] with an error if one occurs during a match selection/download.
  Widget getDownloadMatchUIFor({
    required MatchSource source,
    required void Function(ShootingMatch) onMatchSelected,
    void Function(ShootingMatch)? onMatchDownloaded,
    required void Function(MatchSourceError) onError,
    String? initialSearch,
  });

  static SourceUI forSource(MatchSource source) {
    if(source is PSv2MatchSource) {
      return PSv2UI();
    }
    else if(source is PractiscoreHitFactorReportParser) {
      return PractiscoreReportUI();
    }
    else if(source is SSAServerMatchSource) {
      return SSAServerSourceUI();
    }
    throw StateError("No UI for source $source");
  }

}
