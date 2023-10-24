/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:uspsa_result_viewer/data/source/source.dart';
import 'package:uspsa_result_viewer/data/sport/match/match.dart';
import 'package:uspsa_result_viewer/util.dart';

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
  Future<Result<ShootingMatch, MatchSourceError>> getHitFactorMatch(String id) {
    throw UnimplementedError();
  }

  @override
  Future<Result<ShootingMatch, MatchSourceError>> getMatchFromSearch(MatchSearchResult<InternalMatchType> result) {
    throw UnimplementedError();
  }

  @override
  Future<Result<ShootingMatch, MatchSourceError>> getPointsMatch(String id) {
    throw UnimplementedError();
  }

  @override
  Future<Result<ShootingMatch, MatchSourceError>> getTimePlusPenaltiesMatch(String id) {
    throw UnimplementedError();
  }

  @override
  Future<Result<ShootingMatch, MatchSourceError>> getTimePlusPointsDownMatch(String id) {
    throw UnimplementedError();
  }

  @override
  String get name => "PSv2 Source Stub";

}