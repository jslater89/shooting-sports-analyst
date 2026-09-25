/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "package:flutter_test/flutter_test.dart";
import "package:shooting_sports_analyst/research/mcp/request_args.dart";

void main() {
  group("research request args JSON coercion", () {
    test("SearchMatchesArgs accepts a numeric query", () {
      final args = SearchMatchesArgs.fromJson({
        "query": 2024,
        "limit": "5",
      });
      expect(args.query, "2024");
      expect(args.limit, 5);
    });

    test("SearchMatchesArgs keeps a text query", () {
      final args = SearchMatchesArgs.fromJson({
        "query": "Area 5",
      });
      expect(args.query, "Area 5");
      expect(args.limit, 10);
    });

    test("ShooterLookupArgs accepts a numeric memberNumber", () {
      final args = ShooterLookupArgs.fromJson({
        "memberNumber": 4837,
        "project": "L2s Main LLR",
      });
      expect(args.memberNumber, "4837");
      expect(args.project, "L2s Main LLR");
    });

    test("GetMatchWinnersArgs accepts a string matchId", () {
      final args = GetMatchWinnersArgs.fromJson({
        "matchId": "99",
        "byRatingGroup": "true",
      });
      expect(args.matchId, 99);
      expect(args.byRatingGroup, isTrue);
    });
  });
}
