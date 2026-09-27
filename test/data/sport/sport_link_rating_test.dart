/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:collection/collection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/ipsc.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/links/registry.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/uspsa.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/filter_set.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/shooter.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/data/sport/sport_link.dart';

/// Divisions a rating group will pull from an IPSC match, matching
/// [RatingProjectLoader._getShooters] when the link can be ingested.
Set<Division> ingestDivisions(RatingGroup group, {required Sport matchSport}) {
  final link = SportLinkRegistry().linkFor(source: matchSport, target: group.sport);
  expect(link, isNotNull);
  expect(link!.canIngest, isTrue);
  final filters = link.targetCompatibleFiltersFor(group.divisions);
  expect(filters.mode, FilterMode.or);
  expect(filters.sport, group.sport);
  return filters.activeDivisions.toSet();
}

/// The group a shooter is assigned to, matching [DbRatingProject.groupForDivisionSync].
RatingGroup? groupForDivision(Division division, List<RatingGroup> groups) {
  RatingGroup? assigned;
  var fewestDivisions = 1 << 30;
  for(var group in groups) {
    if(group.divisions.length < fewestDivisions && group.containsDivision(division)) {
      fewestDivisions = group.divisions.length;
      assigned = group;
    }
  }
  return assigned;
}

/// Source divisions mixed into a rating group's career history. Matches
/// the merge in [CareerStats._calculateAnnualStats].
Set<Division> careerDivisions(RatingGroup group) {
  final divisions = [...group.divisions];
  final links = SportLinkRegistry().linksToTarget(group.sport, canIngest: true);
  for(var link in links) {
    final inbound = group.divisions.map((division) => link.sourceCompatibleDivisions(division)).flattenedToSet;
    divisions.addAll(inbound);
  }
  return divisions.toSet();
}

MatchEntry _entry(Division division, int id) {
  return MatchEntry(
    firstName: "Test",
    lastName: division.shortName,
    entryId: id,
    powerFactor: ipscSport.powerFactors.values.first,
    classification: ipscSport.classifications.lookupByName("A", fallback: false),
    division: division,
    scores: {},
  );
}

void main() {
  final uspsaGroups = uspsaSport.builtinRatingGroupsProvider!.builtinRatingGroups;
  RatingGroup uspsaGroup(String uuid) {
    return uspsaGroups.firstWhere((group) => group.uuid == uuid);
  }

  final ipscGroups = ipscSport.builtinRatingGroupsProvider!.divisionRatingGroups;
  RatingGroup ipscGroup(String name) {
    return ipscGroups.firstWhere((group) => group.name == name);
  }

  late ShootingMatch ipscMatch;

  setUp(() {
    var id = 0;
    ipscMatch = ShootingMatch(
      name: "IPSC Nationals",
      rawDate: "2026-09-01",
      date: DateTime(2026, 9, 1),
      sport: ipscSport,
      stages: [],
      shooters: [
        ipscOpen,
        ipscStandard,
        ipscProduction,
        ipscProductionOptics,
        ipscOptics,
        ipscClassic,
        ipscRevolver,
        ipscPccOptics,
        ipscPccIrons,
      ].map((division) => _entry(division, id++)).toList(),
    );
  });

  List<Division> ratedFrom(RatingGroup group) {
    final divisions = ingestDivisions(group, matchSport: ipscSport).toList();
    return ipscMatch.filterShooters(
      filterMode: FilterMode.or,
      divisions: divisions,
      powerFactors: [],
      classes: [],
      allowReentries: false,
    ).map((shooter) => shooter.division!).toList();
  }

  group("IPSC scores ingested into a USPSA rating group", () {
    test("each division group takes only its mapped IPSC division", () {
      expect(ratedFrom(uspsaGroup("uspsa-open")), [ipscOpen]);
      expect(ratedFrom(uspsaGroup("uspsa-limited")), [ipscStandard]);
      expect(ratedFrom(uspsaGroup("uspsa-production")), [ipscProduction]);
      expect(ratedFrom(uspsaGroup("uspsa-carryoptics")), [ipscProductionOptics]);
      expect(ratedFrom(uspsaGroup("uspsa-limited-optics")), [ipscOptics]);
      expect(ratedFrom(uspsaGroup("uspsa-singlestack")), [ipscClassic]);
      expect(ratedFrom(uspsaGroup("uspsa-revolver")), [ipscRevolver]);
      expect(ratedFrom(uspsaGroup("uspsa-pcc")), [ipscPccOptics]);
    });

    test("LO/CO ingests Optics and Production Optics with LO and CO", () {
      final loCo = uspsaGroup("uspsa-lo-co");
      expect(
        ingestDivisions(loCo, matchSport: ipscSport),
        {uspsaLimitedOptics, uspsaCarryOptics, ipscOptics, ipscProductionOptics},
      );
      expect(
        ratedFrom(loCo).toSet(),
        {ipscOptics, ipscProductionOptics},
      );
    });

    test("PCC Iron is not rated with USPSA PCC", () {
      expect(ratedFrom(uspsaGroup("uspsa-pcc")), isNot(contains(ipscPccIrons)));
      expect(uspsaGroup("uspsa-pcc").containsDivision(ipscPccIrons), isFalse);
      expect(groupForDivision(ipscPccIrons, uspsaGroups), isNull);
    });

    test("Limited 10 has no IPSC shooters", () {
      expect(ratedFrom(uspsaGroup("uspsa-limited10")), isEmpty);
    });

    test("a Limited group does not ingest the rest of the IPSC match", () {
      final active = ingestDivisions(uspsaGroup("uspsa-limited"), matchSport: ipscSport);
      expect(active, {uspsaLimited, ipscStandard});
    });

    test("the same sport is not widened by a link", () {
      expect(
        SportLinkRegistry().linkFor(source: uspsaSport, target: uspsaSport),
        isNull,
      );
    });

    test("a backwards division lookup does not invent a source division", () {
      final link = SportLinkRegistry().linkFor(source: ipscSport, target: uspsaSport)!;
      expect(link.targetCompatibleDivision(uspsaLimited), isNull);
      expect(link.targetCompatibleDivisionForName("not a division"), isNull);
    });

    test("shared division names are still distinct objects", () {
      expect(identical(ipscProduction, uspsaProduction), isFalse);
      expect(identical(ipscRevolver, uspsaRevolver), isFalse);
      expect(identical(ipscOpen, uspsaOpen), isFalse);
    });
  });

  group("Assigning an IPSC shooter to a USPSA rating group", () {
    test("Optics lands in Limited Optics, not the combined LO/CO group", () {
      expect(groupForDivision(ipscOptics, uspsaGroups)?.uuid, "uspsa-limited-optics");
    });

    test("Standard lands in Limited, not Open", () {
      expect(groupForDivision(ipscStandard, uspsaGroups)?.uuid, "uspsa-limited");
    });

    test("ingest is required for the cross-sport assignment", () {
      expect(
        uspsaGroup("uspsa-limited-optics").containsDivision(ipscOptics, canIngest: false),
        isFalse,
      );
    });

    test("a USPSA division still uses the group's own divisions", () {
      final open = uspsaGroup("uspsa-open");
      expect(open.containsDivision(uspsaOpen), isTrue);
      expect(open.containsDivision(ipscStandard), isFalse);
    });
  });

  group("Career history divisions", () {
    test("a USPSA group includes the IPSC divisions that feed it", () {
      expect(
        careerDivisions(uspsaGroup("uspsa-limited")),
        {uspsaLimited, ipscStandard},
      );
      expect(
        careerDivisions(uspsaGroup("uspsa-pcc")),
        {uspsaPcc, ipscPccOptics},
      );
      expect(careerDivisions(uspsaGroup("uspsa-limited10")), {uspsaLimited10});
    });
  });

  group("USPSA scores ingested into an IPSC rating group", () {
    test("Limited maps to Standard and PCC maps only to PCC Optics", () {
      final link = SportLinkRegistry().linkFor(source: uspsaSport, target: ipscSport)!;
      expect(link.canIngest, isTrue);
      expect(link.targetCompatibleDivision(uspsaLimited), ipscStandard);
      expect(link.targetCompatibleDivision(uspsaPcc), ipscPccOptics);
      expect(link.targetCompatibleDivision(uspsaLimited10), isNull);

      final standard = ingestDivisions(ipscGroup("Standard"), matchSport: uspsaSport);
      expect(standard, {ipscStandard, uspsaLimited});
    });
  });

  test("a division link with an unknown target name fails instead of falling back", () {
    expect(
      () => SportLink(
        sourceSport: ipscSport,
        targetSport: uspsaSport,
        canIngest: true,
        canPredict: false,
        divisionLinks: [
          DivisionLink(
            sourceDivisions: [ipscOpen],
            targetDivision: const Division(sportName: uspsaSportName, name: "Nope", shortName: "NO"),
          ),
        ],
      ),
      throwsArgumentError,
    );
  });
}
