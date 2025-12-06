/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:http/http.dart' as http;
import 'package:shooting_sports_analyst/closed_sources/ssa_auth_client/auth_client.dart';
import 'package:shooting_sports_analyst/logger.dart';

var _log = SSALogger("SSAAuth");

bool ssaAuthInitialized = false;
SSAPublicAuthClient? _client;

SSAPublicAuthClient get ssaAuthClient => _client != null ? _client! : throw StateError("SSA auth client not initialized");

void initializeAuthClient({
  required String serverBaseUrl,
  required bool allowDebugCertificates,
  required String serverX25519PubBase64,
  required String serverEd25519PubBase64,
}) {
  if(ssaAuthInitialized) {
    return;
  }
  _client = SSAPublicAuthClient(
    baseUrl: serverBaseUrl,
    allowDebugCertificates: allowDebugCertificates,
    serverX25519PubBase64: serverX25519PubBase64,
    serverEd25519PubBase64: serverEd25519PubBase64,
  );
}

Future<http.Response> makeAuthenticatedRequest(
  String method,
  String path, {
  List<int>? bodyBytes,
  Map<String, String>? headers,
}) async {
  var sessionResult = await ssaAuthClient.getSession();
  if (sessionResult.isErr()) {
    throw Exception("Authentication failed: ${sessionResult.unwrapErr().message}");
  }
  var session = sessionResult.unwrap();

  var bodyBytesList = bodyBytes ?? <int>[];
  var authHeaders = await ssaAuthClient.getHeaders(
    session,
    method: method,
    path: path,
    bodyBytes: bodyBytesList,
  );

  var allHeaders = {
    ...authHeaders,
    ...headers ?? {},
  };

  var uri = Uri.parse("${ssaAuthClient.baseUrl}$path");
  http.Response response;
  if (method == "GET") {
    response = await http.get(uri, headers: allHeaders);
  } else if (method == "POST") {
    response = await http.post(uri, headers: allHeaders, body: bodyBytesList);
  } else {
    throw Exception("Unsupported HTTP method: $method");
  }

  // If auth failed, try refreshing session once
  if (response.statusCode == 401) {
    _log.w("Refreshing ostensibly valid session");
      var refreshResult = await ssaAuthClient.refreshSession(session);
    if (refreshResult.isOk()) {
      session = refreshResult.unwrap();
      authHeaders = await ssaAuthClient.getHeaders(
        session,
        method: method,
        path: path,
        bodyBytes: bodyBytesList,
      );
      allHeaders = {
        ...authHeaders,
        ...headers ?? {},
      };
      if (method == "GET") {
        response = await http.get(uri, headers: allHeaders);
      } else if (method == "POST") {
        response = await http.post(uri, headers: allHeaders, body: bodyBytesList);
      }
    }
  }

  return response;
}

bool get isCurrentlyAuthenticated {
  var sessionResult = ssaAuthClient.getCurrentSession();
  return sessionResult.isOk() && sessionResult.unwrap().isValid();
}

Future<void> refreshAuth() async {
  await ssaAuthClient.getSession();
}

