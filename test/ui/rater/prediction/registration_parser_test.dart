/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "package:flutter_test/flutter_test.dart";
import "package:shooting_sports_analyst/data/source/auto_importer.dart";
import "package:shooting_sports_analyst/data/sport/builtins/uspsa.dart";
import "package:shooting_sports_analyst/flutter_native_providers.dart";
import "package:shooting_sports_analyst/server/providers.dart";
import "package:shooting_sports_analyst/ui/rater/prediction/registration_parser.dart";
import "package:shooting_sports_analyst/util.dart";

const _sampleRegistrationHtml = """
<!DOCTYPE html>
<html lang="en"><head>
<meta property="og:title" content="Castlewood August Match">
<meta property="og:url" content="https://practiscore.com/castlewood-august-2026-uspsa-match/squadding">
</head><body>
<div class="squadBox">
  <strong>Squad 101</strong><br>
  <span class="clearable">
    <span title="Matt Young (Open / A)">Matt Young</span>
  </span><br>
  <span class="clearable">
    <span title="Eric Henwood (Limited / B)">Eric Henwood</span>
  </span>
</div>
</body></html>
""";

void main() {
  FlutterOrNative.debugModeProvider = ServerDebugProvider();

  group("Registration HTML helpers", () {
    test("isPractiscoreRegistrationHtml accepts squadding page structure", () {
      expect(isPractiscoreRegistrationHtml(_sampleRegistrationHtml), isTrue);
    });

    test("isPractiscoreRegistrationHtml rejects unrelated text", () {
      expect(isPractiscoreRegistrationHtml("hello world"), isFalse);
      expect(isPractiscoreRegistrationHtml("<html><body>practiscore</body></html>"), isFalse);
    });

    test("extractRegistrationHtmlMetadata reads match id from og:url", () {
      final metadata = extractRegistrationHtmlMetadata(_sampleRegistrationHtml);
      expect(metadata.matchName, "Castlewood August Match");
      expect(metadata.matchId, "castlewood-august-2026-uspsa-match");
      expect(metadata.sportName, isNull);
      expect(metadata.date, isNull);
    });

    test("extractRegistrationHtmlMetadata prefers plugin meta tags", () {
      const htmlWithMeta = """
<!DOCTYPE html><html><head>
<meta name="match-id" content="plugin-match-id">
<meta name="sport-name" content="uspsa">
<meta name="match-date" content="2026-08-15">
<meta property="og:title" content="Plugin Match">
<meta property="og:url" content="https://practiscore.com/og-url-match/squadding">
</head><body>
<div class="squadBox">
  <span class="clearable"><span title="Shooter One (Open / A)">Shooter One</span></span>
</div>
</body></html>
""";
      final metadata = extractRegistrationHtmlMetadata(htmlWithMeta);
      expect(metadata.matchId, "plugin-match-id");
      expect(metadata.sportName, "uspsa");
      expect(metadata.date, programmerYmdFormat.parse("2026-08-15"));
    });

    test("getFutureMatchFromHtml succeeds with sport and date overrides", () async {
      final result = await AutoImporter.getFutureMatchFromHtml(
        _sampleRegistrationHtml,
        sportOverride: uspsaSport,
        dateOverride: DateTime(2026, 8, 15),
      );
      expect(result.isOk(), isTrue);
      final (futureMatch, registrations) = result.unwrap();
      expect(futureMatch.matchId, "castlewood-august-2026-uspsa-match");
      expect(futureMatch.eventName, "Castlewood August Match");
      expect(futureMatch.sportName, uspsaSport.name);
      expect(futureMatch.date, DateTime(2026, 8, 15));
      expect(registrations.length, 2);
      expect(registrations.map((r) => r.shooterName).toSet(), {"Matt Young", "Eric Henwood"});
    });
  });
}
