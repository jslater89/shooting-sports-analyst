/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "package:flutter_test/flutter_test.dart";
import "package:shooting_sports_analyst/config/serialized_config.dart";
import "package:shooting_sports_analyst/data/booth/shooter_overrides.dart";
import "package:shooting_sports_analyst/data/source/match_source_registry.dart";
import "package:shooting_sports_analyst/data/source/ssa_source/ssa_server_source.dart";
import "package:shooting_sports_analyst/data/sport/match/match.dart";
import "package:shooting_sports_analyst/data/sport/shooter/shooter.dart";
import "package:shooting_sports_analyst/flutter_native_providers.dart";
import "package:shooting_sports_analyst/server/providers.dart";

import "dummy_ssa_server.dart";

void main() {
  late BoothDummyServer server;

  setUpAll(() async {
    server = BoothDummyServer();
    final url = await server.start(live: false);
    FlutterOrNative.debugModeProvider = ServerDebugProvider(isDebugMode: true, isMultiIsolate: false);
    FlutterOrNative.configProvider = ServerConfigProvider(SerializedConfig.fromToml({
      "ssaServerBaseUrl": url.toString(),
      "ssaServerStubApiKey": BoothDummyServer.apiKey,
    }));
  });

  tearDownAll(() async {
    await server.stop();
  });

  test("a download comes back Subminor, and reapplying the override keeps Minor across a newer download", () async {
    final source = MatchSourceRegistry().getByCodeOrNull(SSAServerMatchSource.ssaServerCode);
    expect(source, isA<SSAServerMatchSource>());
    final ssa = source! as SSAServerMatchSource;

    final found = await ssa.findMatches("booth");
    expect(found.isOk(), isTrue, reason: found.isErr() ? found.unwrapErr().toString() : "");
    expect(found.unwrap().single.matchId, BoothDummyServer.matchId);

    final first = await ssa.getMatchFromId(BoothDummyServer.matchId);
    expect(first.isOk(), isTrue, reason: first.isErr() ? first.unwrapErr().toString() : "");
    final firstMatch = first.unwrap();
    expect(firstMatch.sourceCode, SSAServerMatchSource.ssaServerCode);

    final pat = _pat(firstMatch);
    expect(pat.powerFactor.name, "Subminor");
    expect(pat.scores.values.single.points, 0);
    final firstHits = _aHits(pat);
    expect(firstHits, server.aHits);

    final store = ShooterOverrideStore.instance;
    final override = ShooterOverride(
      sourceId: BoothDummyServer.patSourceId,
      powerFactorName: "Minor",
      originalPowerFactorName: "Subminor",
    );
    expect(store.applyOverride(firstMatch.sport, pat, override), isTrue);
    expect(pat.powerFactor.name, "Minor");
    final overriddenPoints = pat.scores.values.single.points;
    expect(overriddenPoints, greaterThan(0));

    server.advance();
    final second = await ssa.getMatchFromId(BoothDummyServer.matchId);
    expect(second.isOk(), isTrue, reason: second.isErr() ? second.unwrapErr().toString() : "");
    final secondMatch = second.unwrap();
    final patAgain = _pat(secondMatch);
    expect(patAgain.powerFactor.name, "Subminor");
    expect(_aHits(patAgain), server.aHits);
    expect(_aHits(patAgain), isNot(firstHits));

    expect(store.applyOverride(secondMatch.sport, patAgain, override), isTrue);
    expect(patAgain.powerFactor.name, "Minor");
    expect(_aHits(patAgain), server.aHits);
    expect(patAgain.scores.values.single.points, greaterThan(overriddenPoints));
  });
}

MatchEntry _pat(ShootingMatch match) {
  return match.shooters.firstWhere((s) => s.sourceId == BoothDummyServer.patSourceId);
}

int _aHits(MatchEntry shooter) {
  final score = shooter.scores.values.single;
  final a = score.targetEvents.keys.firstWhere((event) => event.name == "A");
  return score.targetEvents[a]!;
}
