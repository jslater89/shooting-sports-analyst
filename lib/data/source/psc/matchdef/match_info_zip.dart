/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:shooting_sports_analyst/data/source/match_source_error.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/util.dart';

var _log = SSALogger("MatchInfoZip");

class MatchInfoFiles {
  final String matchDefJson;
  final String matchScoresJson;

  MatchInfoFiles({
    required this.matchDefJson,
    required this.matchScoresJson,
  });

  static Result<MatchInfoFiles, MatchSourceError> unzipMatchInfoZip(List<int> zipBytes, {bool useUtf8 = false}) {
    try {
      var archive = ZipDecoder().decodeBytes(zipBytes);
      var matchDef = "";
      var matchScores = "";
      List<String> filesInArchive = [];
      for(var f in archive) {
        if(f.name.contains("match_def")) {
          if(useUtf8) {
            matchDef = utf8.decode(f.content);
          }
          else {
            matchDef = String.fromCharCodes(f.content);
          }
        }
        else if(f.name.contains("match_scores") || f.name.contains("scores")) {
          if(useUtf8) {
            matchScores = utf8.decode(f.content);
          }
          else {
            matchScores = String.fromCharCodes(f.content);
          }
        }
        filesInArchive.add(f.name);
      }

      // // Write matchDef and matchScores to JSON files in /tmp
      // try {
      //   final matchDefFile = File('/tmp/match_def.json');
      //   final matchScoresFile = File('/tmp/match_scores.json');

      //   await matchDefFile.writeAsString(matchDef);
      //   await matchScoresFile.writeAsString(matchScores);

      //   _log.i("Match definition and scores written to /tmp/match_def.json and /tmp/match_scores.json");
      // } catch (e, st) {
      //   _log.e("Error writing match files to /tmp", error: e, stackTrace: st);
      //   // Continue execution, as this is not a critical error
      // }

      if(matchDef.isNotEmpty && matchScores.isNotEmpty) {
        return Result.ok(MatchInfoFiles(matchDefJson: matchDef, matchScoresJson: matchScores));
      }
      else {
        _log.w("no def/scores in zip, files in archive: ${filesInArchive.join(", ")}");
        return Result.err(FormatError(StringError("match info missing subelements: (has def/scores: ${matchDef.isNotEmpty} ${matchScores.isNotEmpty})")));
      }
    }
    on Exception catch(e, st) {
      _log.e("error unzipping match info zip", error: e, stackTrace: st);
      return Result.err(FormatError(NativeException(e)));
    } catch(e, st) {
      _log.e("other error unzipping match info zip", error: e, stackTrace: st);
      return Result.err(FormatError(StringError("unknown error unzipping match info zip: $e")));
    }
  }
}

class ScoreLogs {
  List<Map<String, dynamic>> logs;
  String matchId;

  ScoreLogs({required this.matchId, required this.logs});
}
