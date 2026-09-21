/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "dart:async";
import "dart:convert";
import "dart:io";

import "package:shelf/shelf.dart";
import "package:shelf/shelf_io.dart" as shelf_io;
import "package:shooting_sports_analyst/api/miff/miff.dart";
import "package:shooting_sports_analyst/data/source/ssa_source/ssa_server_source.dart";
import "package:shooting_sports_analyst/data/sport/builtins/uspsa.dart";
import "package:shooting_sports_analyst/data/sport/match/match.dart";
import "package:shooting_sports_analyst/data/sport/scoring/scoring.dart";
import "package:shooting_sports_analyst/data/sport/shooter/shooter.dart";
import "package:shooting_sports_analyst/data/sport/sport.dart";

/// Loopback SSA stand-in for the open auth stub.
///
/// The public client posts `{"apiKey"}` to `/auth/v2/exchange` and then sends
/// `Authorization: Bearer <sessionId>`. This server accepts [apiKey] and serves
/// one USPSA match whose hit counts change over time. Pat Subminor stays
/// Subminor on the wire, so a booth override has to be reapplied after every
/// download or he stops scoring again.
class BoothDummyServer {
  static const String apiKey = "booth-dummy";
  static const String matchId = "booth-dummy-1";
  static const String matchName = "Booth Dummy Match";
  static const String patSourceId = "dummy-pat";

  HttpServer? _http;
  Timer? _timer;
  int tick = 0;
  final Map<String, DateTime> _sessions = {};

  Uri? get url {
    final port = _http?.port;
    if (port == null) return null;
    return Uri.parse("http://127.0.0.1:$port");
  }

  /// [live] advances the match every 2 seconds. Tests leave it off and call
  /// [advance] themselves.
  Future<Uri> start({int port = 0, bool live = true}) async {
    if (live) {
      _timer = Timer.periodic(const Duration(seconds: 2), (_) => tick++);
    }
    _http = await shelf_io.serve(_handle, InternetAddress.loopbackIPv4, port);
    return url!;
  }

  Future<void> stop() async {
    _timer?.cancel();
    await _http?.close(force: true);
    _http = null;
  }

  void advance() {
    tick++;
  }

  /// A-hits on the moving shooters. Oscillates so a long-running server does
  /// not grow the match without bound, and still changes on every tick.
  int get aHits => 4 + (tick % 9);

  ShootingMatch buildMatch() {
    final now = DateTime.now().toUtc();
    final stage = MatchStage(
      stageId: 1,
      name: "Stage 1",
      scoring: uspsaSport.defaultStageScoring,
      minRounds: 12,
      maxPoints: 60,
    );
    final minor = uspsaSport.powerFactors.lookupByName("Minor")!;
    final sub = uspsaSport.powerFactors.lookupByName("Subminor")!;
    final major = uspsaSport.powerFactors.lookupByName("Major")!;

    MatchEntry shooter({
      required String first,
      required String last,
      required int entryId,
      required String sourceId,
      required PowerFactor powerFactor,
      required Division division,
      required int aCount,
      required double time,
      String? memberNumber,
    }) {
      final a = powerFactor.targetEvents.lookupByName("A")!;
      final c = powerFactor.targetEvents.lookupByName("C")!;
      return MatchEntry(
        firstName: first,
        lastName: last,
        entryId: entryId,
        sourceId: sourceId,
        memberNumber: memberNumber ?? "",
        powerFactor: powerFactor,
        division: division,
        scores: {
          stage: RawScore(
            scoring: uspsaSport.defaultStageScoring,
            rawTime: time,
            modified: now,
            targetEvents: {a: aCount, c: 2},
            penaltyEvents: {},
          ),
        },
      );
    }

    return ShootingMatch(
      name: matchName,
      rawDate: "2026-09-21",
      date: DateTime.utc(2026, 9, 21),
      sourceCode: SSAServerMatchSource.ssaServerCode,
      sourceIds: const [matchId],
      sourceLastUpdated: now,
      sport: uspsaSport,
      stages: [stage],
      shooters: [
        shooter(
          first: "Ada",
          last: "Leader",
          entryId: 1,
          sourceId: "dummy-ada",
          powerFactor: minor,
          division: uspsaCarryOptics,
          aCount: aHits,
          time: 18,
        ),
        shooter(
          first: "Pat",
          last: "Subminor",
          entryId: 2,
          sourceId: patSourceId,
          memberNumber: "L0001",
          powerFactor: sub,
          division: uspsaCarryOptics,
          aCount: aHits,
          time: 20,
        ),
        shooter(
          first: "Bea",
          last: "Steady",
          entryId: 3,
          sourceId: "dummy-bea",
          powerFactor: major,
          division: uspsaOpen,
          aCount: 8,
          time: 22,
        ),
      ],
    );
  }

  Future<Response> _handle(Request request) async {
    final path = request.url.path;
    if (request.method == "GET" && (path.isEmpty || path == "/")) {
      return Response.ok(
        "Booth dummy SSA. Match $matchId, api key $apiKey.",
        headers: {"content-type": "text/plain"},
      );
    }
    if (request.method == "POST" && path == "auth/v2/exchange") {
      return _exchange(request);
    }
    if (!_authorized(request)) {
      return Response.unauthorized(
        jsonEncode({"error": "missing or invalid session"}),
        headers: {"content-type": "application/json"},
      );
    }
    if (request.method == "GET" && path == "match/has/$matchId") {
      return Response.ok(
        jsonEncode({"hasMatch": true}),
        headers: {"content-type": "application/json"},
      );
    }
    if (request.method == "GET" && path.startsWith("match/has/")) {
      return Response.ok(
        jsonEncode({"hasMatch": false}),
        headers: {"content-type": "application/json"},
      );
    }
    if (request.method == "GET" && path == "match/$matchId") {
      final exported = MiffExporter().exportMatch(buildMatch());
      if (exported.isErr()) {
        return Response.internalServerError(
          body: jsonEncode({"error": exported.unwrapErr().message}),
          headers: {"content-type": "application/json"},
        );
      }
      return Response.ok(
        exported.unwrap(),
        headers: {"content-type": MiffExporter.compressedMimeType},
      );
    }
    if (request.method == "POST" && path == "match/search") {
      return _search(request);
    }
    return Response.notFound(jsonEncode({"error": "not found"}));
  }

  Future<Response> _exchange(Request request) async {
    Map<String, dynamic> body;
    try {
      body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    }
    catch (_) {
      return Response.badRequest(
        body: jsonEncode({"error": "invalid request body"}),
        headers: {"content-type": "application/json"},
      );
    }
    if (body["apiKey"] != apiKey) {
      return Response.unauthorized(
        jsonEncode({"error": "invalid api key"}),
        headers: {"content-type": "application/json"},
      );
    }
    final sessionId = "booth-session-$tick-${DateTime.now().microsecondsSinceEpoch}";
    _sessions[sessionId] = DateTime.now().toUtc().add(const Duration(hours: 1));
    return Response.ok(
      jsonEncode({
        "sessionId": sessionId,
        "exp": _sessions[sessionId]!.millisecondsSinceEpoch ~/ 1000,
        "roles": ["viewer"],
      }),
      headers: {"content-type": "application/json"},
    );
  }

  bool _authorized(Request request) {
    final header = request.headers["authorization"] ?? "";
    if (!header.toLowerCase().startsWith("bearer ")) return false;
    final token = header.substring(7).trim();
    final exp = _sessions[token];
    if (exp == null || exp.isBefore(DateTime.now().toUtc())) return false;
    return true;
  }

  Future<Response> _search(Request request) async {
    Map<String, dynamic> body;
    try {
      body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    }
    catch (_) {
      return Response.badRequest(
        body: jsonEncode({"error": "invalid query"}),
        headers: {"content-type": "application/json"},
      );
    }
    final query = (body["query"] as String? ?? "").toLowerCase();
    final hit = query.isNotEmpty &&
        (matchName.toLowerCase().contains(query) || matchId.contains(query));
    final results = hit
        ? [
            {
              "matchName": matchName,
              "matchId": matchId,
              "matchDate": DateTime.utc(2026, 9, 21).toIso8601String(),
              "sportName": uspsaSport.type.name,
            }
          ]
        : <Map<String, dynamic>>[];
    return Response.ok(
      jsonEncode(results),
      headers: {"content-type": "application/json"},
    );
  }
}
