/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:uspsa_result_viewer/data/sport/match/match.dart';

abstract class MatchSource {
  bool get isImplemented;
  bool get canSearch;
  /// findMatches may return a MatchSearchResult<T> if needed. See
  /// [InternalMatchType].
  Future<List<MatchSearchResult>> findMatches(String search);
  /// getMatchFrom will always provide one of the MatchSearchResults
  /// returned from [findMatches], so you can assume that the generic
  /// type argument to [MatchSearchResult] will be the same as the one
  /// you provided.
  ///
  /// See also [InternalMatchType].
  Future<ShootingMatch> getMatchFrom(MatchSearchResult result);

  Future<ShootingMatch> getHitFactorMatch(String id);
  Future<ShootingMatch> getTimePlusPointsDownMatch(String id);
  Future<ShootingMatch> getTimePlusPenaltiesMatch(String id);
  Future<ShootingMatch> getPointsMatch(String id);
}

/// A parent class for implementation-specific search result information.
///
/// If, for instance, a source uses different parsers/readers for different
/// kinds of matches, and the correct parser can be determined from a search
/// result, this can be used to store that information.
interface class InternalMatchType {}

/// A match found by interrogating the match source.
///
/// [InternalMatchType] is provided in the event that the match source
/// requires additional information from a search result to parse it correctly.
class MatchSearchResult<T extends InternalMatchType> {
  String matchName;
  String matchId;
  DateTime? matchDate;
  T? matchType;

  MatchSearchResult({
    required this.matchName,
    required this.matchId,
    this.matchDate,
    this.matchType,
  });
}