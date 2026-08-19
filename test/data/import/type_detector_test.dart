/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "dart:io";

import "package:flutter_test/flutter_test.dart";
import "package:shooting_sports_analyst/data/import/type_detector.dart";

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
  </span>
</div>
</body></html>
""";

void main() {
  group("type_detector", () {
    test("detectFormat identifies raw practiscore registration HTML", () async {
      final dir = await Directory.systemTemp.createTemp("ssa_type_detector_test");
      addTearDown(() async {
        await dir.delete(recursive: true);
      });
      final file = File("${dir.path}/squadding.html");
      await file.writeAsString(_sampleRegistrationHtml);

      final format = await detectFormat(file);
      expect(format, FileImportFormat.practiscoreRegistrationHtml);
    });
  });
}
