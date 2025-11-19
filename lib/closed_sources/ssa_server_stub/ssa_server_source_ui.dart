import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/data/source/match_source_error.dart';
import 'package:shooting_sports_analyst/data/source/source.dart';
import 'package:shooting_sports_analyst/data/source/source_ui.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';

class SSAServerSourceUI extends SourceUI {
  @override
  Widget getDownloadMatchUIFor({required MatchSource<InternalMatchType, InternalMatchFetchOptions> source, required void Function(ShootingMatch p1) onMatchSelected, void Function(ShootingMatch p1)? onMatchDownloaded, required void Function(MatchSourceError p1) onError, String? initialSearch}) {
    return Column(
      children: [
        Text("SSA Server Source UI"),
      ],
    );
  }
}