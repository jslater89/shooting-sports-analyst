/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/idpa.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/ipsc.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/uspsa.dart';
import 'package:shooting_sports_analyst/data/sport/predictable_sports.dart';

void main() {
  group("predictableSportsFor", () {
    test("includes prediction-linked source sports", () {
      final names = predictableSportsFor(uspsaSport).map((sport) => sport.name).toSet();
      expect(names, contains(uspsaSportName));
      expect(names, contains(ipscSportName));
      expect(names, isNot(contains(idpaSportName)));
    });

    test("is directed, so the inverse link is a separate set", () {
      final names = predictableSportsFor(ipscSport).map((sport) => sport.name).toSet();
      expect(names, contains(ipscSportName));
      expect(names, contains(uspsaSportName));
    });
  });

  group("sportsForMatchPrepLink", () {
    test("keeps the future match sport when it is not linked", () {
      final names = sportsForMatchPrepLink(
        projectSport: uspsaSport,
        futureMatchSportName: idpaSportName,
      ).map((sport) => sport.name).toSet();
      expect(names, contains(uspsaSportName));
      expect(names, contains(ipscSportName));
      expect(names, contains(idpaSportName));
    });
  });

  group("sportNameIn", () {
    test("matches linked sports case-insensitively", () {
      final sports = predictableSportsFor(uspsaSport);
      expect(sportNameIn("IPSC", sports), isTrue);
      expect(sportNameIn("ipsc", sports), isTrue);
      expect(sportNameIn(idpaSportName, sports), isFalse);
    });
  });
}
