/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/widgets.dart';
import 'package:shooting_sports_analyst/data/database/match/match_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/match.dart';
import 'package:shooting_sports_analyst/data/source/match_source_error.dart';
import 'package:shooting_sports_analyst/data/source/registered_sources.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/util.dart';

/// A MatchSource represents some way to retrieve match data from a remote source,
/// like a database or website. Matches are keyed by a unique ID—for PractiScore, for
/// instance, the key is the long-style UUID.
abstract class MatchSource {
  /// A name suitable for display.
  String get name;

  /// A URL-encodable code for internal identification.
  ///
  /// Match IDs should be prefixed with 'code', so that they don't overlap in the database.
  String get code;

  /// If this source can handle codes from other sources, it should contain [code]s for
  /// those sources in this array. It should also include its own code.
  List<String> get handledCodes => [code];

  String removeCode(String matchId) {
    return matchId.replaceFirst("$code:", "");
  }

  String applyCode(String matchId) {
    if(matchId.startsWith("$code:")) return matchId;
    else return "$code:$matchId";
  }

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
  ///
  /// A caller providing [typeHint] expects a match of the provided type. In the event that
  /// the ID maps to a match, but the type is wrong, the match source should return
  /// [MatchSourceError.typeMismatch].
  ///
  /// A caller providing [sport] requires a match belonging to the provided sport.
  Future<Result<ShootingMatch, MatchSourceError>> getMatchFromSearch(MatchSearchResult result, {SportType? typeHint, Sport? sport});

  /// Get a match identified by the given ID.
  ///
  /// A caller providing [typeHint] expects a match of the provided type. In the event that
  /// the ID maps to a match, but the type is wrong, the match source should return
  /// [MatchSourceError.typeMismatch].
  ///
  /// A caller providing [sport] requires a match belonging to the provided sport.
  Future<Result<ShootingMatch, MatchSourceError>> getMatchFromId(String id, {SportType? typeHint, Sport? sport});

  /// Return the UI to be displayed in the 'get match' dialog.
  ///
  /// The returned UI should fit an 800px by 500px box (or allow scrolling, if taller
  /// than 500px). The enclosing UI will provide 'cancel' or 'back' functionality.
  ///
  /// Call [onMatchSelected] with a match if one is selected and downloaded.
  Widget getDownloadMatchUI(void Function(ShootingMatch) onMatchSelected);

  static Future<Result<ShootingMatch, MatchSourceError>> reloadMatch(DbShootingMatch match) async {
    var source = MatchSourceRegistry().getByCodeOrNull(match.sourceCode);

    if(source == null || !source.isImplemented) {
      return Result.err(UnsupportedMatchType("No source for ${match.sourceCode}"));
    }

    var result = await source.getMatchFromId(match.sourceIds.first, sport: match.sport);

    if(result.isOk()) {
      var match = result.unwrap();
      var r = await AnalystDatabase().saveMatch(match);
      if(r.isOk()) {
        match.databaseId = r.unwrap().id;
        return Result.ok(match);
      }
      else {
        return Result.err(GeneralError(r.unwrapErr()));
      }
    }
    else {
      return Result.errFrom(result);
    }
  }
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