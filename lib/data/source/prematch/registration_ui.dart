import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/match.dart';
import 'package:shooting_sports_analyst/data/source/match_source_error.dart';
import 'package:shooting_sports_analyst/data/source/prematch/registration.dart';
import 'package:shooting_sports_analyst/data/source/ssa_source/ssa_server_registration_source.dart';
import 'package:shooting_sports_analyst/data/source/ssa_source/ssa_server_registration_source_ui.dart';

abstract class FutureMatchSourceUI {
  Widget getDownloadMatchUIFor({
    required FutureMatchSource source,
    required void Function(FutureMatch) onMatchSelected,
    void Function(FutureMatch)? onMatchDownloaded,
    required void Function(MatchSourceError) onError,
    String? initialSearch,
  });

  static FutureMatchSourceUI forSource(FutureMatchSource source) {
    if(source is SSAServerFutureMatchSource) {
      return SSAServerFutureMatchSourceUI();
    }
    throw UnimplementedError("No UI for source $source");
  }
}