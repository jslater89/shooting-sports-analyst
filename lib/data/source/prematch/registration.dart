/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/data/database/schema/match_prep/match.dart';
import 'package:shooting_sports_analyst/data/source/match_source_error.dart';
import 'package:shooting_sports_analyst/data/source/search.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/util.dart';

typedef FutureMatchSearchResult = Result<List<FutureMatchSearchHit>, MatchSourceError>;
typedef FutureMatchResult = Result<FutureMatch, MatchSourceError>;

/// A source to retrieve registration and other information about future matches.
///
///
abstract class FutureMatchSource {
  /// The name of the source.
  String get name;

  /// The code of the source.
  String get code;

  /// The supported sports of the source.
  List<SportType> get supportedSports;

  /// Whether the source is implemented (true) or a stub (false).
  bool get isImplemented => false;

  /// Whether the source can search by name.
  bool get canSearchByName => false;

  /// Whether the source can filter searches by sport.
  bool get canFilterSearchesBySport => false;

  /// Search for matches by name.
  Future<FutureMatchSearchResult> searchByName(String name, {List<Sport>? sportFilter}) {
    return Future.value(Result.err(MatchSourceError.unsupportedOperation));
  }

  /// Get a match by its ID (returned as part of the search results).
  Future<FutureMatchResult> getMatchById(String id) {
    return Future.value(Result.err(MatchSourceError.unsupportedOperation));
  }
}

class FutureMatchSearchHit {
  /// The name of the match.
  String matchName;
  /// The ID of the match, suitable for retrieving it with the /<matchId> endpoint.
  String matchId;
  /// The date of the match.
  DateTime matchStartDate;
  /// The end date of the match.
  DateTime? matchEndDate;
  /// The match's sport name.
  String sportName;

  FutureMatchSearchHit({
    required this.matchName,
    required this.matchId,
    required this.matchStartDate,
    this.matchEndDate,
    required this.sportName,
  });

  Map<String, dynamic> toJson() {
    return {
      "matchName": matchName,
      "matchId": matchId,
      "matchStartDate": matchStartDate.toIso8601String(),
      "matchEndDate": matchEndDate?.toIso8601String(),
      "sportName": sportName,
    };
  }

  static FutureMatchSearchHit fromJson(Map<String, dynamic> json) {
    return FutureMatchSearchHit(
      matchName: json["matchName"],
      matchId: json["matchId"],
      matchStartDate: DateTime.parse(json["matchStartDate"]),
      matchEndDate: json["matchEndDate"] != null ? DateTime.parse(json["matchEndDate"]) : null,
      sportName: json["sportName"],
    );
  }

  static FutureMatchSearchHit fromFutureMatch(FutureMatch match) {
    return FutureMatchSearchHit(
      matchName: match.eventName,
      matchId: match.matchId,
      matchStartDate: match.date,
      sportName: match.sportName,
    );
  }
}
