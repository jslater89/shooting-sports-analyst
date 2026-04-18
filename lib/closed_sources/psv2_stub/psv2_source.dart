/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

/*
This is the PSv2 stub.
 */

import 'dart:convert';

import 'package:shooting_sports_analyst/data/source/match_source_error.dart';
import 'package:shooting_sports_analyst/data/source/psc/matchdef/bare_match_def.dart';
import 'package:shooting_sports_analyst/data/source/psc/matchdef/hitfactor/converter.dart';
import 'package:shooting_sports_analyst/data/source/psc/matchdef/icore/converter.dart';
import 'package:shooting_sports_analyst/data/source/psc/matchdef/idpa/converter.dart';
import 'package:shooting_sports_analyst/data/source/psc/matchdef/match_info_zip.dart';
import 'package:shooting_sports_analyst/data/source/psc/psc_options.dart';
import 'package:shooting_sports_analyst/data/source/source.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/util.dart';

final _log = SSALogger("PSv2MatchSource");

/*
This is a stub file. The full PSv2 source is implemented elsewhere.
 */
class PSv2MatchSource extends MatchSource {
  @override
  bool get canSearch => false;

  @override
  bool get isImplemented => false;

  @override
  Future<Result<List<MatchSearchResult<InternalMatchType>>, MatchSourceError>> findMatches(String search) {
    throw UnimplementedError();
  }

  @override
  Future<Result<ShootingMatch, MatchSourceError>> getMatchFromSearch(MatchSearchResult<InternalMatchType> result, {Sport? sport, SportType? typeHint, InternalMatchFetchOptions? options}) {
    throw UnimplementedError();
  }

  @override
  String get name => "PSv2 Source Stub";

  @override
  List<SportType> get supportedSports => [];

  static const String psv2Code = "psv2";
  @override
  String get code => psv2Code;

  @override
  Future<Result<ShootingMatch, MatchSourceError>> getMatchFromId(String id, {Sport? sport, SportType? typeHint, InternalMatchFetchOptions? options}) {
    // TODO: implement getMatchFromId
    throw UnimplementedError();
  }

  Future<Result<ShootingMatch, MatchSourceError>> getMatchFromInfoFiles(MatchInfoFiles matchInfoFiles, {PscMatchFetchOptions? options}) async {
    BareMatchDef bareMatchDef;
    try {
      bareMatchDef = BareMatchDef.fromJson(jsonDecode(matchInfoFiles.matchDefJson));
      bareMatchDef.scoresJson = jsonDecode(matchInfoFiles.matchScoresJson);
    } catch(e, stackTrace) {
      _log.e("Error parsing match def: $e", stackTrace: stackTrace);
      return Result.err(FormatError(StringError("Error parsing match def: $e")));
    }

    var matchType = PscMatchType.fromString(bareMatchDef.matchType);
    if(matchType == null) {
      return Result.err(FormatError(StringError("Unknown match type: ${bareMatchDef.matchType}")));
    }

    switch(matchType) {
      case PscMatchType.hitFactor:
        return HitFactorConverter.matchFromBareMatchDef(bareMatchDef, options: options);
      case PscMatchType.idpaLike:
        return IdpaConverter.matchFromBareMatchDef(bareMatchDef, options: options);
      case PscMatchType.icoreLike:
        return IcoreConverter.matchFromBareMatchDef(bareMatchDef, options: options);
      default:
        return Result.err(MatchSourceError.unsupportedMatchType);
    }
  }
}
