/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:convert';

import 'package:shelf_plus/shelf_plus.dart';
import 'package:shooting_sports_analyst/api/riff/impl/riff_exporter.dart';
import 'package:shooting_sports_analyst/api/riff/impl/riff_importer.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/extensions/match_prep.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/match.dart';
import 'package:shooting_sports_analyst/data/source/prematch/registration.dart';

class RegistrationService {
  AnalystDatabase database = AnalystDatabase();
  RegistrationService([List<Middleware> middleware = const []]) {
    for(final m in middleware) {
      router.use(m);
    }
    router.post("/search", searchFutureMatches);
    router.get("/<registrationId>", getFutureMatch);
    router.post("/upload", uploadFutureMatch);
  }

  final router = Router().plus;

  /// GET /<registrationId>
  ///
  /// Returns the [FutureMatch] with the given ID, if available. Note that registration IDs
  /// are not the same as match IDs.
  ///
  /// Returns 404 if the match is not found.
  Future<Response> getFutureMatch(Request request, String registrationId) async {
    var registration = await database.getFutureMatchByMatchId(registrationId);
    if(registration == null) {
      return Response.notFound("Registration not found");
    }

    var riff = RiffExporter().exportMatch(registration);
    if(riff.isErr()) {
      return Response.internalServerError(body: "Failed to export match");
    }
    return Response.ok(riff.unwrap(), headers: {
      "Content-Type": RiffExporter.compressedMimeType,
    });
  }

  /// POST /search
  ///
  /// Search for match registration data by match name.
  ///
  /// Search term is in the JSON body as {"query": "term"}.
  Future<Response> searchFutureMatches(Request request) async {
    var body = await request.body.asJson;
    if(body == null || body is! Map<String, dynamic>) {
      return Response.badRequest(body: "Invalid request");
    }
    var query = body["query"] as String;
    if(query.isEmpty) {
      return Response.badRequest(body: "Invalid query");
    }
    var registrations = await database.getFutureMatchesByName(query);
    var searchResults = registrations.map((m) => FutureMatchSearchHit.fromFutureMatch(m)).toList();
    var searchJson = jsonEncode(searchResults.map((m) => m.toJson()).toList());
    return Response.ok(searchJson, headers: {
      "Content-Type": "application/json",
    });
  }

  /// POST /upload
  ///
  /// Upload a future match in RIFF format.
  Future<Response> uploadFutureMatch(Request request) async {
    var bodyBytes = await request.body.asBinary.reduce((a, b) => a + b);
    var importRes = RiffImporter().importMatch(bodyBytes);
    if(importRes.isErr()) {
      return Response.badRequest(body: jsonEncode({"error": importRes.unwrapErr().message}));
    }
    var match = importRes.unwrap();
    await database.saveFutureMatch(match, newRegistrations: match.registrations.toList());
    return Response.ok(jsonEncode({"success": "Match uploaded"}));
  }
}
