/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:convert';

import 'package:shooting_sports_analyst/api/riff/impl/riff_exporter.dart';
import 'package:shooting_sports_analyst/api/riff/impl/riff_importer.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/match.dart';
import 'package:shooting_sports_analyst/data/source/match_source_error.dart';
import 'package:shooting_sports_analyst/data/source/prematch/registration.dart';
import 'package:shooting_sports_analyst/data/source/ssa_source/ssa_auth.dart';
import 'package:shooting_sports_analyst/data/source/ssa_source/ssa_server_source.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/flutter_native_providers.dart';
import 'package:shooting_sports_analyst/util.dart';

class SSAServerFutureMatchSource extends FutureMatchSource {

  SSAServerFutureMatchSource();

  void initialize() {
    var configProvider = FlutterOrNative.configProvider;
    var config = configProvider.currentConfig;
    var debugMode = FlutterOrNative.debugModeProvider.kDebugMode;
    var serverBaseUrl = config.ssaServerBaseUrl;
    var serverX25519PubBase64 = config.ssaServerX25519PubBase64;
    var serverEd25519PubBase64 = config.ssaServerEd25519PubBase64;

    initializeAuthClient(
      serverBaseUrl: serverBaseUrl,
      allowDebugCertificates: debugMode,
      serverX25519PubBase64: serverX25519PubBase64,
      serverEd25519PubBase64: serverEd25519PubBase64,
    );
  }
  @override
  String get name => "SSA Server";
  @override
  String get code => SSAServerMatchSource.ssaServerCode;

  @override
  List<SportType> get supportedSports => SportType.values;

  @override
  bool get isImplemented => true;
  @override
  bool get canSearchByName => true;
  @override
  bool get canFilterSearchesBySport => false;

  @override
  Future<FutureMatchSearchResult> searchByName(String name, {List<Sport>? sportFilter}) async {
    var bodyBytes = utf8.encode(jsonEncode({"query": name}));
    var response = await makeAuthenticatedRequest("POST", "/registration/search", bodyBytes: bodyBytes);
    if(response.statusCode != 200) {
      return Result.err(NetworkErrorWithResponse(response));
    }
    var json = jsonDecode(utf8.decode(response.bodyBytes)) as List;
    var results = <FutureMatchSearchHit>[];
    for(var item in json) {
      results.add(FutureMatchSearchHit.fromJson(item));
    }
    return Result.ok(results);
  }

  @override
  Future<FutureMatchResult> getMatchById(String id) async {
    var response = await makeAuthenticatedRequest("GET", "/registration/$id");
    if(response.statusCode != 200) {
      return Result.err(NetworkErrorWithResponse(response));
    }

    var riff = RiffImporter().importMatch(response.bodyBytes);
    if(riff.isErr()) {
      return Result.err(FormatError(riff.unwrapErr()));
    }
    return Result.ok(riff.unwrap());
  }

  bool get canUpload {
    var sessionResult = ssaAuthClient.getCurrentSession();
    if(sessionResult.isErr()) {
      return false;
    }
    var session = sessionResult.unwrap();
    return session.hasAnyRole(["uploader", "admin"]);
  }

  Future<MatchSourceError?> uploadMatch(FutureMatch match) async {
    if(!canUpload) {
      return MatchSourceError.noCredentials;
    }
    var riff = RiffExporter().exportMatch(match);
    if(riff.isErr()) {
      return FormatError(riff.unwrapErr());
    }
    var bodyBytes = riff.unwrap();
    var response = await makeAuthenticatedRequest("POST", "/registration/upload", bodyBytes: bodyBytes);
    if(response.statusCode != 200) {
      return NetworkErrorWithResponse(response);
    }
    return null;
  }
}