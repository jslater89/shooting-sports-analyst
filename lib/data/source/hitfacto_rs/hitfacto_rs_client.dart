/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "dart:convert";

import "package:http/http.dart" as http;
import "package:shooting_sports_analyst/config/serialized_config.dart";
import "package:shooting_sports_analyst/data/source/hitfacto_rs/hitfacto_rs_models.dart";
import "package:shooting_sports_analyst/flutter_native_providers.dart";
import "package:shooting_sports_analyst/data/source/match_source_error.dart";
import "package:shooting_sports_analyst/logger.dart";
import "package:shooting_sports_analyst/util.dart";

final _log = SSALogger("HitfactoRsClient");

/// HTTP client for [https://hitfacto.rs](https://hitfacto.rs) public API.
class HitfactoRsClient {
  static const String baseHost = "hitfacto.rs";
  static const String baseUrl = "https://hitfacto.rs";

  /// Reads API key from [SerializedConfig.hitfactoRsApiKey] (empty = unauthenticated).
  static String get _apiKeyFromConfig =>
      FlutterOrNative.configProvider.currentConfig.hitfactoRsApiKey.trim();

  static Map<String, String> _headers() {
    final h = <String, String>{
      "Accept": "application/json",
      "User-Agent": "ShootingSportsAnalyst/1.0 (Dart)",
    };
    final key = _apiKeyFromConfig;
    if (key.isNotEmpty) {
      h["X-API-Key"] = key;
    }
    return h;
  }

  static Result<Map<String, dynamic>, MatchSourceError> _decodeObject(
    http.Response response,
  ) {
    if (response.statusCode == 404) {
      return Result.err(MatchSourceError.notFound);
    }
    if (response.statusCode == 429) {
      return Result.err(
        GeneralError(StringError("Rate limited: ${response.body}")),
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return Result.err(NetworkErrorWithResponse(response));
    }
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        return Result.ok(decoded);
      }
      return Result.err(FormatError(StringError("Expected JSON object")));
    } catch (e, st) {
      _log.e("JSON decode error", error: e, stackTrace: st);
      if (e is Exception) {
        return Result.err(FormatError(NativeException(e)));
      }
      return Result.err(FormatError(StringError("$e")));
    }
  }

  /// [GET /v1/matches](https://hitfacto.rs/openapi.json) — search matches (cursor pagination).
  static Future<Result<HitfactoRsMatchListPage, MatchSourceError>> listMatches({
    String? query,
    String? cursor,
    int limit = 50,
  }) async {
    try {
      final uri = Uri.https(baseHost, "/v1/matches", {
        if (query != null && query.isNotEmpty) "q": query,
        if (cursor != null && cursor.isNotEmpty) "cursor": cursor,
        "limit": "$limit",
      });
      final response = await http.get(uri, headers: _headers());
      final decoded = _decodeObject(response);
      if (decoded.isErr()) {
        return Result.errFrom(decoded);
      }
      return Result.ok(HitfactoRsMatchListPage.fromJson(decoded.unwrap()));
    } catch (e, st) {
      _log.e("listMatches HTTP error", error: e, stackTrace: st);
      return Result.err(MatchSourceError.networkError);
    }
  }

  /// [GET /v1/matches/{uuid}](https://hitfacto.rs/openapi.json).
  static Future<Result<HitfactoRsMatchDetail, MatchSourceError>> getMatch(
    String matchUuid,
  ) async {
    try {
      final uri = Uri.https(baseHost, "/v1/matches/$matchUuid");
      final response = await http.get(uri, headers: _headers());
      final decoded = _decodeObject(response);
      if (decoded.isErr()) {
        return Result.errFrom(decoded);
      }
      return Result.ok(HitfactoRsMatchDetail.fromJson(decoded.unwrap()));
    } catch (e, st) {
      _log.e("getMatch HTTP error", error: e, stackTrace: st);
      return Result.err(MatchSourceError.networkError);
    }
  }

  /// [GET /v1/matches/{uuid}/results](https://hitfacto.rs/openapi.json) — one page.
  static Future<Result<HitfactoRsResultsPage, MatchSourceError>> getResultsPage(
    String matchUuid, {
    String? cursor,
    int limit = 200,
  }) async {
    try {
      final uri = Uri.https(baseHost, "/v1/matches/$matchUuid/results", {
        if (cursor != null && cursor.isNotEmpty) "cursor": cursor,
        "limit": "$limit",
      });
      final response = await http.get(uri, headers: _headers());
      final decoded = _decodeObject(response);
      if (decoded.isErr()) {
        return Result.errFrom(decoded);
      }
      return Result.ok(HitfactoRsResultsPage.fromJson(decoded.unwrap()));
    } catch (e, st) {
      _log.e("getResultsPage HTTP error", error: e, stackTrace: st);
      return Result.err(MatchSourceError.networkError);
    }
  }

  /// Walks cursor pagination until all result rows are read.
  static Future<Result<List<HitfactoRsResultRow>, MatchSourceError>>
  getAllResults(String matchUuid) async {
    final all = <HitfactoRsResultRow>[];
    String? cursor;
    var hasMore = true;
    while (hasMore) {
      final pageResult = await getResultsPage(matchUuid, cursor: cursor);
      if (pageResult.isErr()) {
        return Result.errFrom(pageResult);
      }
      final page = pageResult.unwrap();
      all.addAll(page.data);
      hasMore =
          page.hasMore &&
          page.nextCursor != null &&
          page.nextCursor!.isNotEmpty;
      cursor = page.nextCursor;
    }
    return Result.ok(all);
  }
}
