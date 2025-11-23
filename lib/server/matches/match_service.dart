/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:convert';

import 'package:shelf_plus/shelf_plus.dart';
import 'package:shooting_sports_analyst/api/miff/miff.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/match.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';

class MatchService {
  MatchService([List<Middleware> middleware = const []]) {
    for(final m in middleware) {
      router.use(m);
    }
    router.get("/<matchId>", getMatch);
    router.post("/search", search);
  }

  final database = AnalystDatabase();
  final router = Router().plus;

  /// GET /<matchId>
  ///
  /// Return the match with the given source ID in MIFF format.
  ///
  /// Returns 404 if the match is not found.
  dynamic getMatch(Request request, String matchId) async {
    var match = await database.getMatchBySourceId(matchId);
    if(match == null) {
      return Response.notFound("Match not found");
    }
    var hydratedRes = match.hydrate();
    if(hydratedRes.isErr()) {
      return Response.internalServerError(body: "Failed to hydrate match");
    }
    var hydrated = hydratedRes.unwrap();
    var miff = MiffExporter().exportMatch(hydrated);
    if(miff.isErr()) {
      return Response.internalServerError(body: "Failed to export match");
    }
    return Response.ok(miff.unwrap());
  }

  /// /search
  ///
  /// Searches for matches by name, returning a list of match search results.
  Future<Response> search(Request request) async {
    // Search in {"query": "term"} in the body
    var body = await request.body.asJson;
    if(body == null || body is! Map<String, dynamic>) {
      return Response.badRequest(body: "Invalid query");
    }
    var query = body["query"] as String;
    if(query.isEmpty) {
      return Response.badRequest(body: "Invalid query");
    }
    var matches = await database.matchNameTextSearch(query, limit: 25);
    var matchJson = jsonEncode(matches.map((m) => MatchSearchResult.fromDbMatch(m).toJson()).toList());
    return Response.ok(matchJson);
  }
}

class MatchSearchResult {
  /// The name of the match.
  String matchName;
  /// The ID of the match, suitable for retrieving it with the /<matchId> endpoint.
  String matchId;
  /// The date of the match.
  DateTime matchDate;
  /// The match's sport name.
  String sportName;

  MatchSearchResult({
    required this.matchName,
    required this.matchId,
    required this.matchDate,
    required this.sportName,
  });

  Map<String, dynamic> toJson() {
    return {
      "matchName": matchName,
      "matchId": matchId,
      "matchDate": matchDate.toIso8601String(),
      "sportName": sportName,
    };
  }

  static MatchSearchResult fromDbMatch(DbShootingMatch match) {
    return MatchSearchResult(
      matchName: match.eventName,
      matchId: match.sourceIds.first,
      matchDate: match.date,
      sportName: match.sportName,
    );
  }

  static MatchSearchResult fromMatch(ShootingMatch match) {
    return MatchSearchResult(
      matchName: match.name,
      matchId: match.sourceIds.first,
      matchDate: match.date,
      sportName: match.sport.name,
    );
  }
}