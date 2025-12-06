/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "dart:convert";

import "package:http/http.dart" as http;
import "package:shooting_sports_analyst/api/miff/miff.dart";
import "package:shooting_sports_analyst/data/database/analyst_database.dart";
import "package:shooting_sports_analyst/data/source/match_source_error.dart";
import "package:shooting_sports_analyst/data/source/source.dart";
import "package:shooting_sports_analyst/data/source/ssa_source/ssa_auth.dart";
import "package:shooting_sports_analyst/data/sport/match/match.dart";
import "package:shooting_sports_analyst/data/sport/sport.dart";
import "package:shooting_sports_analyst/flutter_native_providers.dart";
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

class SSAServerMatchFetchOptions extends InternalMatchFetchOptions {
  /// The time of the last update to the match. If provided, the source will return a local copy of the
  /// match if it has not been updated since the provided time.
  ///
  /// If not provided, the source will always retrieve a full match from the server.
  DateTime? lastUpdated;

  SSAServerMatchFetchOptions({this.lastUpdated});

  @override
  String toString() {
    return "SSAServerMatchFetchOptions(lastUpdated: $lastUpdated)";
  }
}

class SSAServerMatchSource extends MatchSource<ServerMatchType, SSAServerMatchFetchOptions> {
  late final String baseUrl;
  bool _initialized = false;
  bool get initialized => _initialized;

  SSAServerMatchSource();

  void initialize() {
    var configProvider = FlutterOrNative.configProvider;
    var config = configProvider.currentConfig;
    var debugMode = FlutterOrNative.debugModeProvider.kDebugMode;
    var serverBaseUrl = config.ssaServerBaseUrl;
    var serverX25519PubBase64 = config.ssaServerX25519PubBase64;
    var serverEd25519PubBase64 = config.ssaServerEd25519PubBase64;

    baseUrl = serverBaseUrl;
    initializeAuthClient(
      serverBaseUrl: serverBaseUrl,
      allowDebugCertificates: debugMode,
      serverX25519PubBase64: serverX25519PubBase64,
      serverEd25519PubBase64: serverEd25519PubBase64,
    );
  }

  @override
  bool get canSearch => true;

  @override
  bool get isImplemented => true;

  @override
  String get name => "SSA Server";

  bool get canUpload {
    var sessionResult = ssaAuthClient.getCurrentSession();
    if(sessionResult.isErr()) {
      return false;
    }
    var session = sessionResult.unwrap();
    return session.hasAnyRole(["uploader", "admin"]);
  }

  Future<MatchSourceError?> uploadMatch(ShootingMatch match) async {
    if(!canUpload) {
      return MatchSourceError.noCredentials;
    }
    var miff = MiffExporter().exportMatch(match);
    if(miff.isErr()) {
      return FormatError(miff.unwrapErr());
    }
    var bodyBytes = miff.unwrap();
    var response = await makeAuthenticatedRequest("POST", "/match/upload", bodyBytes: bodyBytes);
    if(response.statusCode != 200) {
      return NetworkErrorWithResponse(response);
    }
    return null;
  }

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

  @override
  Future<Result<List<MatchSearchResult<ServerMatchType>>, MatchSourceError>> findMatches(String search) async {
    try {
      var bodyBytes = utf8.encode(jsonEncode({"query": search}));
      var response = await makeAuthenticatedRequest("POST", "/match/search", bodyBytes: bodyBytes);

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
    SSAServerMatchFetchOptions? options,
  }) async {
    return getMatchFromId(result.matchId, typeHint: typeHint, sport: sport, options: options);
  }

  @override
  Future<Result<ShootingMatch, MatchSourceError>> getMatchFromId(
    String id, {
    SportType? typeHint,
    Sport? sport,
    SSAServerMatchFetchOptions? options,
  }) async {
    try {
      var response = await makeAuthenticatedRequest("GET", "/match/$id", headers: options?.lastUpdated != null ? {"If-Modified-Since": options!.lastUpdated!.toUtc().toIso8601String()} : null);

      if (response.statusCode == 404) {
        return Result.err(MatchSourceError.notFound);
      }

      if (response.statusCode == 304) {
        var localCopy = await AnalystDatabase().getMatchBySourceId(id);
        if(localCopy == null) {
          return Result.err(MatchSourceError.notModified);
        }
        var hydrateRes = localCopy.hydrate();
        if(hydrateRes.isErr()) {
          return Result.err(GeneralError(StringError("Failed to hydrate local copy: ${hydrateRes.unwrapErr().message}")));
        }
        return Result.ok(hydrateRes.unwrap());
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

