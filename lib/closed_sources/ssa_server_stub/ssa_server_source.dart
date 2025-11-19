/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "package:shooting_sports_analyst/data/source/match_source_error.dart";
import "package:shooting_sports_analyst/data/source/source.dart";
import "package:shooting_sports_analyst/data/sport/match/match.dart";
import "package:shooting_sports_analyst/data/sport/sport.dart";
import "package:shooting_sports_analyst/util.dart";

/*
 * This is a stub file. The full SSAServer source is implemented elsewhere.
 */
enum ServerMatchType implements InternalMatchType {
  uspsa,
  ipsc,
  pcsl,
  idpa,
  icore,
  generic;
}

class SSAServerMatchSource extends MatchSource<ServerMatchType, InternalMatchFetchOptions> {
  @override
  bool get canSearch => false;

  @override
  bool get isImplemented => false;

  @override
  Future<Result<List<MatchSearchResult<ServerMatchType>>, MatchSourceError>> findMatches(String search) {
    throw UnimplementedError();
  }

  @override
  Future<Result<ShootingMatch, MatchSourceError>> getMatchFromSearch(
    MatchSearchResult<ServerMatchType> result, {
    Sport? sport,
    SportType? typeHint,
    InternalMatchFetchOptions? options,
  }) {
    throw UnimplementedError();
  }

  @override
  String get name => "SSA Server Source Stub";

  @override
  List<SportType> get supportedSports => [];

  static const String ssaServerCode = "ssa_server";
  @override
  String get code => ssaServerCode;

  @override
  Future<Result<ShootingMatch, MatchSourceError>> getMatchFromId(
    String id, {
    Sport? sport,
    SportType? typeHint,
    InternalMatchFetchOptions? options,
  }) {
    throw UnimplementedError();
  }
}

