/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:uspsa_result_viewer/data/source/source.dart';
import 'package:uspsa_result_viewer/data/sport/match/match.dart';

class PSv2MatchSource extends MatchSource {
  @override
  bool get canSearch => false;

  @override
  Future<List<MatchSearchResult<InternalMatchType>>> findMatches(String search) {
    throw UnimplementedError();
  }

  @override
  Future<ShootingMatch> getHitFactorMatch(String id) {
    throw UnimplementedError();
  }

  @override
  Future<ShootingMatch> getMatchFrom(MatchSearchResult<InternalMatchType> result) {
    throw UnimplementedError();
  }

  @override
  Future<ShootingMatch> getPointsMatch(String id) {
    throw UnimplementedError();
  }

  @override
  Future<ShootingMatch> getTimePlusPenaltiesMatch(String id) {
    throw UnimplementedError();
  }

  @override
  Future<ShootingMatch> getTimePlusPointsDownMatch(String id) {
    throw UnimplementedError();
  }

  @override
  bool get isImplemented => false;

}