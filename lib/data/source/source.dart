/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:uspsa_result_viewer/data/source/match_source_error.dart';
import 'package:uspsa_result_viewer/data/sport/sport.dart';
import 'package:uspsa_result_viewer/data/sport/match/match.dart';
import 'package:uspsa_result_viewer/util.dart';

/// A MatchSource represents some way to retrieve match data from a remote source,
/// like a database or website. Matches are keyed by a unique ID—for PractiScore, for
/// instance, the key is the long-style UUID.
abstract class MatchSource {
  /// A name suitable for display.
  String get name;
  /// A URL-encodable code for internal identification.
  String get code;
  bool get isImplemented;
  bool get canSearch;
  List<SportType> get supportedSports;
  
  /// findMatches may return a MatchSearchResult<T> if needed. See
  /// [InternalMatchType].
  Future<Result<List<MatchSearchResult>, MatchSourceError>> findMatches(String search);

  /// Given a search result, get the match it corresponds to.
  ///
  /// getMatchFrom will always provide one of the MatchSearchResults
  /// returned from [findMatches], so you can assume that the generic
  /// type argument to [MatchSearchResult] will be the same as the one
  /// you provided.
  ///
  /// See also [InternalMatchType].
  Future<Result<ShootingMatch, MatchSourceError>> getMatchFromSearch(MatchSearchResult result);

  /// Get a match identified by the given ID.
  ///
  /// A caller providing [typeHint] expects a match of the provided type. In the event that
  /// the ID maps to a match, but the type is wrong, the match source should return
  /// [MatchSourceError.typeMismatch].
  Future<Result<ShootingMatch, MatchSourceError>> getMatchFromId(String id, {SportType? typeHint});

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
  String matchSubtype;
  String matchId;
  DateTime? matchDate;
  T? matchType;

  MatchSearchResult({
    required this.matchName,
    required this.matchId,
    required this.matchSubtype,
    this.matchDate,
    this.matchType,
  });
}