/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:uspsa_result_viewer/data/sport/sport.dart';
import 'package:uspsa_result_viewer/util.dart';
import 'package:uspsa_result_viewer/data/sport/match/match.dart';

enum MatchSourceError implements Error {
  /// A network error occurred when fetching the match.
  networkError,
  /// This source cannot provide a match of the requested type.
  unsupportedMatchType,
  /// This source does not support the given operation.
  unsupportedOperation,
  /// An ID provided to a get-match-of-type method does not correspond
  /// to the correct kind of match.
  incorrectMatchType,
  /// This source was unable to parse the data retrieved from the given
  /// ID.
  formatError;

  String get message => switch(this) {
    networkError => "Network error",
    unsupportedOperation => "Source does not support operation",
    unsupportedMatchType => "Source does not support match type",
    incorrectMatchType => "Provided match ID is invalid for requested match type",
    formatError => "Error parsing match data",
  };
}

abstract class MatchSource {
  String get name;
  bool get isImplemented;
  bool get canSearch;
  List<SportType> get supportedSports;
  
  /// findMatches may return a MatchSearchResult<T> if needed. See
  /// [InternalMatchType].
  Future<Result<List<MatchSearchResult>, MatchSourceError>> findMatches(String search);
  /// getMatchFrom will always provide one of the MatchSearchResults
  /// returned from [findMatches], so you can assume that the generic
  /// type argument to [MatchSearchResult] will be the same as the one
  /// you provided.
  ///
  /// See also [InternalMatchType].
  Future<Result<ShootingMatch, MatchSourceError>> getMatchFromSearch(MatchSearchResult result);

  Future<Result<ShootingMatch, MatchSourceError>> getHitFactorMatch(String id);
  Future<Result<ShootingMatch, MatchSourceError>> getTimePlusPointsDownMatch(String id);
  Future<Result<ShootingMatch, MatchSourceError>> getTimePlusPenaltiesMatch(String id);
  Future<Result<ShootingMatch, MatchSourceError>> getPointsMatch(String id);
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