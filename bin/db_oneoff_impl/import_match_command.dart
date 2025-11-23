import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:dart_console/src/console.dart';
import 'package:shooting_sports_analyst/closed_sources/psv2/matchdef/bare_match_def.dart';
import 'package:shooting_sports_analyst/closed_sources/psv2/matchdef/hitfactor/converter.dart';
import 'package:shooting_sports_analyst/closed_sources/psv2/matchdef/hitfactor/hitfactor_matchdef.dart';
import 'package:shooting_sports_analyst/closed_sources/psv2/matchdef/hitfactor/hitfactor_scores.dart';
import 'package:shooting_sports_analyst/closed_sources/psv2/matchdef/icore/converter.dart';
import 'package:shooting_sports_analyst/closed_sources/psv2/matchdef/icore/icore_matchdef.dart';
import 'package:shooting_sports_analyst/closed_sources/psv2/matchdef/icore/icore_scores.dart';
import 'package:shooting_sports_analyst/closed_sources/psv2/matchdef/idpa/converter.dart';
import 'package:shooting_sports_analyst/closed_sources/psv2/matchdef/idpa/idpa_matchdef.dart';
import 'package:shooting_sports_analyst/closed_sources/psv2/matchdef/idpa/idpa_scores.dart';
import 'package:shooting_sports_analyst/closed_sources/psv2/matchdef/match_info_zip.dart';
import 'package:shooting_sports_analyst/closed_sources/psv2/psv2_code.dart';
import 'package:shooting_sports_analyst/console/repl.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/registry.dart';
import 'package:shooting_sports_analyst/data/sport/model.dart';

import 'base.dart';

class ImportMatchCommand extends DbOneoffCommand {
  ImportMatchCommand(AnalystDatabase db) : super(db);

  @override
  final String key = "IM";
  @override
  final String title = "Import Match";

  @override
  List<MenuArgument> get arguments => [
    StringMenuArgument(label: "sport", description: "Sport to import the match for", required: true),
    StringMenuArgument(label: "file", description: "Path to a match file or directory to import", required: true),
  ];

  @override
  Future<void> executor(Console console, List<MenuArgumentValue> arguments) async {
    var sportName = arguments[0].value as String;
    var sport = SportRegistry().lookup(sportName, caseSensitive: false);
    if(sport == null) {
      console.print("Sport not found: ${sportName}");
      return;
    }
    var path = arguments[1].value as String;
    var file = File(path);
    if(!file.existsSync()) {
      console.print("File does not exist: ${file.path}");
      return;
    }
    var bytes = file.readAsBytesSync();
    var zipFile = ZipDecoder().decodeBytes(bytes);
    String? metadata;
    String? scores;
    for(var entry in zipFile) {
      var entryPath = entry.name;
      console.print("Entry: $entryPath");
      if(entryPath.contains("scores")) {
        scores = utf8.decode(entry.content);
        // For heaven's sake, people, stop with the nicknames
        scores = scores.replaceAll(r"\u201c", '"').replaceAll(r"\u201d", '"');
      }
      else if(entryPath.contains("def")) {
        metadata = utf8.decode(entry.content);
        // I say again...
        metadata = metadata.replaceAll(r"\u201c", '"').replaceAll(r"\u201d", '"');
      }
    }

    if(scores == null) {
      console.print("Could not find scores in the zip file");
      return;
    }
    if(metadata == null) {
      console.print("Could not find metadata in the zip file");
      return;
    }

    var matchInfoFiles = MatchInfoFiles(matchDefJson: metadata, matchScoresJson: scores);
    ShootingMatch? match;

    if(sport.type.isHitFactor) {
      try {
        var matchDef = HitFactorMatchDef.fromJson(jsonDecode(matchInfoFiles.matchDefJson));
        var scores = HitFactorScores.fromJson(jsonDecode(matchInfoFiles.matchScoresJson));
        match = HitFactorConverter.toMatch(sport, matchDef, scores);
        match.sourceIds = [matchDef.uuid];
      }
      catch(e, stackTrace) {
        console.print("Error converting match to HitFactor match: $e");
        console.print("Stack trace: $stackTrace");
        return;
      }
    }
    else if(sport.type == SportType.icore) {
      try {
        var matchDef = IcoreMatchDef.fromJson(jsonDecode(matchInfoFiles.matchDefJson));
        var scores = IcoreScores.fromJson(jsonDecode(matchInfoFiles.matchScoresJson));
        match = IcoreConverter.toMatch(sport, matchDef, scores);
        match.sourceIds = [matchDef.uuid];
      }
      catch(e, stackTrace) {
        console.print("Error converting match to ICORE match: $e");
        console.print("Stack trace: $stackTrace");
        return;
      }
    }
    else if(sport.type == SportType.idpa) {
      try {
        var matchDef = IdpaLikeMatchDef.fromJson(jsonDecode(matchInfoFiles.matchDefJson));
        var scores = IdpaLikeScores.fromJson(jsonDecode(matchInfoFiles.matchScoresJson));
        match = IdpaConverter.toMatch(sport, matchDef, scores);
        match.sourceIds = [matchDef.uuid];
      }
      catch(e, stackTrace) {
        console.print("Error converting match to IDPA match: $e");
        console.print("Stack trace: $stackTrace");
        return;
      }
    }
    else {
      console.print("Unsupported sport type: ${sport.name}/${sport.type}");
      return;
    }
    match.sourceCode = psv2Code;
    await db.saveMatch(match);
    console.print("Match imported successfully: ${match.name}");
  }
}