/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "dart:convert";

import "package:http/http.dart" as http;
import "package:shooting_sports_analyst/api/miff/miff.dart";
import "package:shooting_sports_analyst/closed_sources/ssa_auth_client/auth_client.dart";
import "package:shooting_sports_analyst/data/source/match_source_error.dart";
import "package:shooting_sports_analyst/data/source/source.dart";
import "package:shooting_sports_analyst/data/sport/match/match.dart";
import "package:shooting_sports_analyst/data/sport/sport.dart";
import "package:shooting_sports_analyst/logger.dart";
import "package:shooting_sports_analyst/util.dart";

var _log = SSALogger("SSAServerSource");

enum ServerMatchType implements InternalMatchType {
  uspsa,
  ipsc,
  pcsl,
  idpa,
  icore,
  generic;
}

class SSAServerMatchSource extends MatchSource<ServerMatchType, InternalMatchFetchOptions> {
  final String baseUrl;
  late final SSAPublicAuthClient _authClient;

  SSAServerMatchSource({required this.baseUrl}) {
    _authClient = SSAPublicAuthClient(baseUrl: baseUrl);
  }

  @override
  bool get canSearch => true;

  @override
  bool get isImplemented => true;

  @override
  String get name => "SSA Server";

  @override
  List<SportType> get supportedSports => [
    SportType.uspsa,
    SportType.ipsc,
    SportType.pcsl,
    SportType.idpa,
    SportType.icore,
  ];

  static const String ssaServerCode = "ssa_server";
  @override
  String get code => ssaServerCode;

  Future<http.Response> _makeAuthenticatedRequest(
    String method,
    String path, {
    List<int>? bodyBytes,
  }) async {
    var sessionResult = await _authClient.getSession();
    if (sessionResult.isErr()) {
      throw Exception("Authentication failed: ${sessionResult.unwrapErr().message}");
    }
    var session = sessionResult.unwrap();

    var bodyBytesList = bodyBytes ?? <int>[];
    var headers = await _authClient.getHeaders(
      session,
      method: method,
      path: path,
      bodyBytes: bodyBytesList,
    );

    var uri = Uri.parse("$baseUrl$path");
    http.Response response;
    if (method == "GET") {
      response = await http.get(uri, headers: headers);
    } else if (method == "POST") {
      response = await http.post(uri, headers: headers, body: bodyBytesList);
    } else {
      throw Exception("Unsupported HTTP method: $method");
    }

    // If auth failed, try refreshing session once
    if (response.statusCode == 401) {
      _log.w("Refreshing ostensibly valid session");
      var refreshResult = await _authClient.refreshSession(session);
      if (refreshResult.isOk()) {
        session = refreshResult.unwrap();
        headers = await _authClient.getHeaders(
          session,
          method: method,
          path: path,
          bodyBytes: bodyBytesList,
        );
        if (method == "GET") {
          response = await http.get(uri, headers: headers);
        } else if (method == "POST") {
          response = await http.post(uri, headers: headers, body: bodyBytesList);
        }
      }
    }

    return response;
  }

  @override
  Future<Result<List<MatchSearchResult<ServerMatchType>>, MatchSourceError>> findMatches(String search) async {
    try {
      var bodyBytes = utf8.encode(jsonEncode({"query": search}));
      var response = await _makeAuthenticatedRequest("POST", "/match/search", bodyBytes: bodyBytes);

      if (response.statusCode != 200) {
        _log.e("Search failed with status ${response.statusCode}: ${response.body}");
        return Result.err(NetworkErrorWithResponse(response));
      }

      var json = jsonDecode(utf8.decode(response.bodyBytes)) as List;
      var results = <MatchSearchResult<ServerMatchType>>[];

      for (var item in json) {
        var matchJson = item as Map<String, dynamic>;
        var matchName = matchJson["matchName"] as String;
        var matchId = matchJson["matchId"] as String;
        var matchDateStr = matchJson["matchDate"] as String;
        var matchDate = DateTime.parse(matchDateStr);
        var sportName = matchJson["sportName"] as String;

        // Map sport name to match type
        ServerMatchType? matchType;
        try {
          var sportType = SportType.values.firstWhere((st) => st.name == sportName.toLowerCase());
          matchType = switch (sportType) {
            SportType.uspsa => ServerMatchType.uspsa,
            SportType.ipsc => ServerMatchType.ipsc,
            SportType.pcsl => ServerMatchType.pcsl,
            SportType.idpa => ServerMatchType.idpa,
            SportType.icore => ServerMatchType.icore,
            _ => ServerMatchType.generic,
          };
        } catch (e) {
          matchType = ServerMatchType.generic;
        }

        results.add(MatchSearchResult<ServerMatchType>(
          matchName: matchName,
          matchId: matchId,
          matchSubtype: sportName,
          matchDate: matchDate,
          matchType: matchType,
        ));
      }

      return Result.ok(results);
    } catch (e, st) {
      _log.e("Error searching matches", error: e, stackTrace: st);
      return Result.err(GeneralError(StringError("Search failed: $e")));
    }
  }

  @override
  Future<Result<ShootingMatch, MatchSourceError>> getMatchFromSearch(
    MatchSearchResult<ServerMatchType> result, {
    SportType? typeHint,
    Sport? sport,
    InternalMatchFetchOptions? options,
  }) async {
    return getMatchFromId(result.matchId, typeHint: typeHint, sport: sport, options: options);
  }

  @override
  Future<Result<ShootingMatch, MatchSourceError>> getMatchFromId(
    String id, {
    SportType? typeHint,
    Sport? sport,
    InternalMatchFetchOptions? options,
  }) async {
    try {
      var response = await _makeAuthenticatedRequest("GET", "/match/$id");

      if (response.statusCode == 404) {
        return Result.err(MatchSourceError.notFound);
      }

      if (response.statusCode != 200) {
        _log.e("Get match failed with status ${response.statusCode}: ${response.body}");
        return Result.err(NetworkErrorWithResponse(response));
      }

      // Parse MIFF format
      var miffBytes = response.bodyBytes;
      var importer = MiffImporter();
      var matchResult = importer.importMatch(miffBytes);

      if (matchResult.isErr()) {
        _log.e("Failed to import MIFF: ${matchResult.unwrapErr().message}");
        return Result.err(FormatError(matchResult.unwrapErr()));
      }

      var match = matchResult.unwrap();
      match.sourceCode = code;
      // Ensure the source ID is set correctly
      if (!match.sourceIds.contains(id)) {
        match.sourceIds = [id, ...match.sourceIds];
      }

      return Result.ok(match);
    } catch (e, st) {
      _log.e("Error getting match", error: e, stackTrace: st);
      return Result.err(GeneralError(StringError("Get match failed: $e")));
    }
  }
}

