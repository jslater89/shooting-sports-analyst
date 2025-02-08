/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

/*
This is the PSv2 stub.
 */

import 'package:flutter/src/widgets/framework.dart';
import 'package:shooting_sports_analyst/data/source/match_source_error.dart';
import 'package:shooting_sports_analyst/data/source/source.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/util.dart';

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

  @override
  Widget getDownloadMatchUI({required void Function(ShootingMatch) onMatchSelected, String? initialSearch}) {
    // TODO: implement getDownloadMatchUI
    throw UnimplementedError();
  }
}