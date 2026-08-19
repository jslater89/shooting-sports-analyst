/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

/// Simulates a 50,000-member USPSA coattendance graph using observed
/// 2025-2026 major-match participation counts.
///
/// All 50,000 members are treated as one division. The supplied unique-person
/// major thresholds are reproduced exactly without assigning division splits.
///
/// Run with:
///   dart run research/connectivity/uspsa_major_profile_simulation.dart

import "dart:math";

import "package:collection/collection.dart";

import "connectivity_simulation.dart" as core;

const int kSeed = 20252026;
const int kMemberCount = 50000;
const int kRegionCount = 50;
const int kClubsPerRegion = 8;
const int kSimulationDays = 730;

const int kAnyMajorCount = 11118;
const int kAnnualMajorCount = 3761;
const int kFrequentMajorCount = 2244;

const List<String> kMethodNames = [
  "sqrt",
  "carriers",
  "effective",
  "credit",
];

enum MajorCohort {
  localOnly,
  occasional,
  annual,
  frequent,
}

class MemberProfile {
  final int id;
  final MajorCohort cohort;
  final int homeRegion;
  final int primaryClub;
  final int? secondaryClub;
  final List<int> satelliteClubs;
  final List<int> majorAttendanceYears = [];
  int localMatchCount = 0;
  int generatedLocalMatchCount = 0;
  int generatedMajorMatchCount = 0;
  final Set<int> generatedMajorYears = {};
  final Set<int> generatedLocalClubs = {};

  MemberProfile({
    required this.id,
    required this.cohort,
    required this.homeRegion,
    required this.primaryClub,
    required this.secondaryClub,
    required this.satelliteClubs,
  });

  int chooseLocalClub(Random random) {
    var roll = random.nextDouble();
    if (roll < 0.45) {
      return primaryClub;
    }
    if (roll < 0.75) {
      return secondaryClub ?? primaryClub;
    }
    if (satelliteClubs.isEmpty) {
      return secondaryClub ?? primaryClub;
    }
    return satelliteClubs[random.nextInt(satelliteClubs.length)];
  }
}

class AttendanceToken {
  final int memberId;
  final int year;

  const AttendanceToken({
    required this.memberId,
    required this.year,
  });
}

class PlannedMatch {
  final DateTime date;
  final core.MatchKind kind;
  final List<int> regions;
  final List<AttendanceToken> entries;
  final int? clubId;

  const PlannedMatch({
    required this.date,
    required this.kind,
    required this.regions,
    required this.entries,
    this.clubId,
  });
}

void main() {
  var random = Random(kSeed);
  print("Building 50,000-Member USPSA Population...");
  print("Model: One Division, Multi-Club Regions, Nonlinear Major/Local Activity");
  var members = _buildMembers(random);
  _assignParticipation(members, random);
  _verifyInputMarginals(members);

  print("Generating Local And Major Matches...");
  var generationWatch = Stopwatch()..start();
  var plannedMatches = <PlannedMatch>[
    ..._generateLocalMatches(members, random),
    ..._generateMajorMatches(members, random),
  ]..sort((a, b) => a.date.compareTo(b.date));
  generationWatch.stop();

  var plannedEntries = plannedMatches.map((m) => m.entries.length).sum;
  print("Generated ${plannedMatches.length} Matches And $plannedEntries Entries "
      "In ${generationWatch.elapsedMilliseconds}ms");

  print("Processing Connectivity...");
  var competitors = <int, core.Competitor>{
    for (var member in members)
      member.id: core.Competitor(
        member.id,
        switch (member.cohort) {
          MajorCohort.localOnly => core.CompetitorKind.localLow,
          MajorCohort.occasional => core.CompetitorKind.localHigh,
          MajorCohort.annual => core.CompetitorKind.localHigh,
          MajorCohort.frequent => core.CompetitorKind.traveler,
        },
        member.homeRegion,
        member.primaryClub,
      ),
  };
  var tracker = core.ConnectivityTracker();
  var processedMatches = <core.Match>[];

  for (var matchId = 0; matchId < plannedMatches.length; matchId++) {
    var planned = plannedMatches[matchId];
    var match = core.Match(
      matchId,
      planned.date,
      planned.kind,
      planned.regions,
    );
    for (var entry in planned.entries) {
      match.competitorIds.add(entry.memberId);
      competitors[entry.memberId]!.matchIds.add(matchId);
      if (planned.kind != core.MatchKind.club) {
        members[entry.memberId].generatedMajorMatchCount++;
        members[entry.memberId].generatedMajorYears.add(planned.date.year);
      }
      else if (planned.clubId != null) {
        members[entry.memberId].generatedLocalMatchCount++;
        members[entry.memberId].generatedLocalClubs.add(planned.clubId!);
      }
    }
    tracker.processMatch(
      match,
      {
        for (var id in match.competitorIds)
          id: competitors[id]!,
      },
    );
    processedMatches.add(match);
    if ((matchId + 1) % 500 == 0) {
      print("  Processed ${matchId + 1}/${plannedMatches.length}");
    }
  }

  _analyze(
    members: members,
    competitors: competitors,
    matches: processedMatches,
    tracker: tracker,
    generationMs: generationWatch.elapsedMilliseconds,
  );
}

List<MemberProfile> _buildMembers(Random random) {
  var members = <MemberProfile>[];
  for (var id = 0; id < kMemberCount; id++) {
    var cohort = switch (id) {
      < kFrequentMajorCount => MajorCohort.frequent,
      < kAnnualMajorCount => MajorCohort.annual,
      < kAnyMajorCount => MajorCohort.occasional,
      _ => MajorCohort.localOnly,
    };
    var region = random.nextInt(kRegionCount);
    var regionClubStart = region * kClubsPerRegion;
    var primaryClub = regionClubStart + random.nextInt(kClubsPerRegion);
    int? secondaryClub;
    if (random.nextDouble() < 0.80) {
      do {
        secondaryClub = regionClubStart + random.nextInt(kClubsPerRegion);
      } while (secondaryClub == primaryClub);
    }
    var satelliteTarget = 3 + random.nextInt(2);
    var satelliteClubs = <int>{};
    while (satelliteClubs.length < satelliteTarget) {
      var club = regionClubStart + random.nextInt(kClubsPerRegion);
      if (club != primaryClub && club != secondaryClub) {
        satelliteClubs.add(club);
      }
    }
    members.add(MemberProfile(
      id: id,
      cohort: cohort,
      homeRegion: region,
      primaryClub: primaryClub,
      secondaryClub: secondaryClub,
      satelliteClubs: satelliteClubs.toList(),
    ));
  }
  return members;
}

void _assignParticipation(List<MemberProfile> members, Random random) {
  for (var member in members) {
    var targetMajorCount = switch (member.cohort) {
      MajorCohort.occasional => _sampleOccasionalMajorCount(random),
      MajorCohort.annual => 2 + random.nextInt(2),
      MajorCohort.frequent => _sampleFrequentMajorCount(random),
      MajorCohort.localOnly => 0,
    };

    if (member.cohort == MajorCohort.occasional) {
      var year = random.nextInt(2);
      member.majorAttendanceYears.addAll(
        List<int>.filled(targetMajorCount, year),
      );
    }
    else if (member.cohort == MajorCohort.annual ||
        member.cohort == MajorCohort.frequent) {
      member.majorAttendanceYears.addAll([0, 1]);
      while (member.majorAttendanceYears.length < targetMajorCount) {
        member.majorAttendanceYears.add(random.nextInt(2));
      }
      member.majorAttendanceYears.shuffle(random);
    }

    member.localMatchCount = _poisson(
      _localMatchMean(targetMajorCount, member.cohort, random),
      random,
    );
  }
}

void _verifyInputMarginals(List<MemberProfile> members) {
  var anyMajor = members.where((m) => m.majorAttendanceYears.isNotEmpty).length;
  var annual = members.where((m) =>
      m.majorAttendanceYears.contains(0) &&
      m.majorAttendanceYears.contains(1)).length;
  var frequent = members.where((m) => m.majorAttendanceYears.length >= 4).length;
  if (anyMajor != kAnyMajorCount ||
      annual != kAnnualMajorCount ||
      frequent != kFrequentMajorCount) {
    throw StateError("Major Threshold Marginals Do Not Match: "
        "$anyMajor/$annual/$frequent");
  }
  print("Input Major-Participation Marginals Verified.");
}

List<PlannedMatch> _generateLocalMatches(
  List<MemberProfile> members,
  Random random,
) {
  var matches = <PlannedMatch>[];
  var attendanceByClub = <int, Map<int, int>>{};
  for (var member in members) {
    for (var i = 0; i < member.localMatchCount; i++) {
      var club = member.chooseLocalClub(random);
      var attendance = attendanceByClub.putIfAbsent(club, () => {});
      attendance[member.id] = (attendance[member.id] ?? 0) + 1;
    }
  }

  for (var clubEntry in attendanceByClub.entries) {
    var totalAttendance = clubEntry.value.values.sum;
    var minimumForVolume = (totalAttendance / 40).ceil();
    var minimumForOneEntryPerShooter = clubEntry.value.values.max;
    var clubMatchCount = max(minimumForVolume, minimumForOneEntryPerShooter);
    var clubMatches = List<PlannedMatch>.generate(
      clubMatchCount,
      (_) => PlannedMatch(
        date: _randomDate(random),
        kind: core.MatchKind.club,
        regions: [clubEntry.key ~/ kClubsPerRegion],
        entries: [],
        clubId: clubEntry.key,
      ),
    );

    var memberEntries = clubEntry.value.entries.toList()
      ..shuffle(random)
      ..sort((a, b) => b.value.compareTo(a.value));
    for (var memberEntry in memberEntries) {
      var matchIndexes = List<int>.generate(clubMatchCount, (index) => index)
        ..shuffle(random)
        ..sort((a, b) =>
            clubMatches[a].entries.length.compareTo(clubMatches[b].entries.length));
      if (memberEntry.value > matchIndexes.length) {
        throw StateError("Not Enough Club Matches For ${memberEntry.key}");
      }
      for (var i = 0; i < memberEntry.value; i++) {
        clubMatches[matchIndexes[i]].entries.add(AttendanceToken(
          memberId: memberEntry.key,
          year: -1,
        ));
      }
    }
    matches.addAll(clubMatches);
  }
  return matches;
}

List<PlannedMatch> _generateMajorMatches(
  List<MemberProfile> members,
  Random random,
) {
  var tokenGroups = <(int, int), List<AttendanceToken>>{};
  for (var member in members) {
    for (var year in member.majorAttendanceYears) {
      var nationalProbability = switch (member.majorAttendanceYears.length) {
        >= 10 => 0.80,
        >= 4 => 0.55,
        _ => switch (member.cohort) {
        MajorCohort.annual => 0.25,
        MajorCohort.occasional => 0.10,
        _ => 0.0,
        },
      };
      var circuit = random.nextDouble() < nationalProbability
          ? -1
          : member.homeRegion ~/ 5;
      tokenGroups.putIfAbsent((year, circuit), () => []).add(AttendanceToken(
        memberId: member.id,
        year: year,
      ));
    }
  }

  var matches = <PlannedMatch>[];
  for (var group in tokenGroups.entries) {
    var year = group.key.$1;
    var circuit = group.key.$2;
    var national = circuit == -1;
    var byMember = group.value.groupListsBy((token) => token.memberId);
    var typicalSize = national ? 260 : 160;
    var minimumForVolume = (group.value.length / typicalSize).ceil();
    var minimumForOneEntryPerShooter = byMember.values.map((tokens) => tokens.length).max;
    var groupMatchCount = max(minimumForVolume, minimumForOneEntryPerShooter);
    var groupMatches = List<PlannedMatch>.generate(
      groupMatchCount,
      (_) => PlannedMatch(
        date: _randomDate(random, year: year),
        kind: national ? core.MatchKind.national : core.MatchKind.area,
        regions: national
            ? [for (var region = 0; region < kRegionCount; region++) region]
            : [for (var offset = 0; offset < 5; offset++) circuit * 5 + offset],
        entries: [],
      ),
    );

    var memberEntries = byMember.entries.toList()
      ..shuffle(random)
      ..sort((a, b) => b.value.length.compareTo(a.value.length));
    for (var memberEntry in memberEntries) {
      var matchIndexes = List<int>.generate(groupMatchCount, (index) => index)
        ..shuffle(random)
        ..sort((a, b) =>
            groupMatches[a].entries.length.compareTo(groupMatches[b].entries.length));
      var tokens = memberEntry.value..shuffle(random);
      if (tokens.length > matchIndexes.length) {
        throw StateError("Not Enough Major Matches For ${memberEntry.key}");
      }
      for (var i = 0; i < tokens.length; i++) {
        groupMatches[matchIndexes[i]].entries.add(tokens[i]);
      }
    }

    for (var match in groupMatches) {
      if (match.entries.length < 8) {
        throw StateError("Generated Major Match With Fewer Than Eight Entries");
      }
    }
    for (var tokens in byMember.values) {
      for (var token in tokens) {
        if (groupMatches.where((match) =>
            match.entries.any((entry) => entry.memberId == token.memberId)).length !=
            tokens.length) {
          throw StateError("Duplicate Major Match Placement For ${token.memberId}");
        }
        break;
      }
    }
    matches.addAll(groupMatches);
  }
  return matches;
}

int _sampleOccasionalMajorCount(Random random) {
  var roll = random.nextDouble();
  if (roll < 0.70) {
    return 1;
  }
  if (roll < 0.95) {
    return 2;
  }
  return 3;
}

int _sampleFrequentMajorCount(Random random) {
  var roll = random.nextDouble();
  if (roll < 0.70) {
    return 4 + random.nextInt(3);
  }
  if (roll < 0.90) {
    return 7 + random.nextInt(3);
  }
  return 10 + random.nextInt(7);
}

double _localMatchMean(
  int majorCount,
  MajorCohort cohort,
  Random random,
) {
  double mean;
  if (cohort == MajorCohort.localOnly) {
    var roll = random.nextDouble();
    mean = switch (roll) {
      < 0.70 => 0.5,
      < 0.90 => 4.0,
      < 0.98 => 12.0,
      _ => 30.0,
    };
  }
  else if (majorCount <= 6) {
    // Four majors over two years corresponds to roughly two local matches per
    // month. Local activity rises with major participation through this band.
    mean = 12.0 + 8.0 * majorCount;
  }
  else {
    // The highest-volume major shooters increasingly replace local matches
    // with majors rather than adding both indefinitely.
    mean = max(2.0, 60.0 - 12.0 * (majorCount - 6));
  }

  // Add heavy-tailed individual variation while preserving the mean.
  const sigma = 0.35;
  var u1 = random.nextDouble().clamp(1e-12, 1.0);
  var u2 = random.nextDouble();
  var z = sqrt(-2 * log(u1)) * cos(2 * pi * u2);
  return mean * exp(sigma * z - 0.5 * sigma * sigma);
}

int _poisson(double lambda, Random random) {
  var limit = exp(-lambda);
  var product = 1.0;
  var count = 0;
  do {
    count++;
    product *= random.nextDouble();
  } while (product > limit);
  return count - 1;
}

DateTime _randomDate(Random random, {int? year}) {
  var dayOffset = year == null
      ? random.nextInt(kSimulationDays)
      : year * 365 + random.nextInt(365);
  return DateTime(2025, 1, 1).add(Duration(
    days: dayOffset,
    minutes: random.nextInt(24 * 60),
  ));
}

void _analyze({
  required List<MemberProfile> members,
  required Map<int, core.Competitor> competitors,
  required List<core.Match> matches,
  required core.ConnectivityTracker tracker,
  required int generationMs,
}) {
  var activeMembers = members.where((m) => competitors[m.id]!.matchIds.isNotEmpty).toList();
  var totalEntries = matches.map((m) => m.competitorIds.length).sum;
  var mathMs = tracker.mathWatch.elapsedMilliseconds;

  print("\n========== USPSA Major-Profile Simulation ==========");
  print("Members: ${members.length}");
  print("Active Members: ${activeMembers.length}");
  print("Generated Unique Major Shooters: "
      "${members.where((m) => m.generatedMajorMatchCount > 0).length}");
  print("Generated Annual Major Shooters: "
      "${members.where((m) => m.generatedMajorYears.length == 2).length}");
  print("Generated Four-Plus Major Shooters: "
      "${members.where((m) => m.generatedMajorMatchCount >= 4).length}");
  print("Matches: ${matches.length}");
  print("Entries: $totalEntries");
  print("Generation Time: ${generationMs}ms");
  print("Connectivity Math Time: ${mathMs}ms");
  print("Projected 200k Connectivity Time: "
      "${(mathMs / totalEntries * 200000).toStringAsFixed(0)}ms");

  print("\n========== Input Cohorts ==========");
  _printTable(
    ["Cohort", "People", "Local Matches", "Major Matches", "Local Clubs", "Recent Majors"],
    [
      for (var cohort in MajorCohort.values)
        _cohortActivityRow(
          members.where((m) => m.cohort == cohort).toList(),
          competitors,
        ),
    ],
  );

  print("\n========== Activity By Major Count ==========");
  _printTable(
    ["Major Count", "People", "Local Matches", "Local Clubs", "sqrt", "effective", "credit"],
    [
      _majorCountBandRow("0", members.where((m) => m.generatedMajorMatchCount == 0).toList(), competitors),
      _majorCountBandRow("1", members.where((m) => m.generatedMajorMatchCount == 1).toList(), competitors),
      _majorCountBandRow("2-3", members.where((m) => m.generatedMajorMatchCount >= 2 && m.generatedMajorMatchCount <= 3).toList(), competitors),
      _majorCountBandRow("4-6", members.where((m) => m.generatedMajorMatchCount >= 4 && m.generatedMajorMatchCount <= 6).toList(), competitors),
      _majorCountBandRow("7-9", members.where((m) => m.generatedMajorMatchCount >= 7 && m.generatedMajorMatchCount <= 9).toList(), competitors),
      _majorCountBandRow("10+", members.where((m) => m.generatedMajorMatchCount >= 10).toList(), competitors),
    ],
  );

  print("\n========== Competitor Metrics By Major Cohort ==========");
  _printTable(
    ["Cohort", "n", "U", "T", "D_eff", "Q", "Regions", ...kMethodNames],
    [
      for (var cohort in MajorCohort.values)
        _cohortMetricRow(
          members.where((m) => m.cohort == cohort).toList(),
          competitors,
        ),
    ],
  );

  print("\n========== Match Metrics ==========");
  _printTable(
    ["Type", "n", "Size", "Coverage", "Efficiency", "Carriers", ...kMethodNames],
    [
      for (var kind in [
        core.MatchKind.club,
        core.MatchKind.area,
        core.MatchKind.national,
      ])
        _matchMetricRow(matches.where((m) => m.kind == kind).toList()),
    ],
  );

  print("\n========== Metric Correlations ==========");
  _printTable(
    ["Method", "Major Count", "Local Count", "Recent Majors", "Mean Field"],
    [
      for (var method in kMethodNames)
        [
          method,
          _spearman(
            members.map((m) => competitors[m.id]!.scores[method]).toList(),
            members.map((m) => m.generatedMajorMatchCount.toDouble()).toList(),
          ).toStringAsFixed(3),
          _spearman(
            members.map((m) => competitors[m.id]!.scores[method]).toList(),
            members.map((m) => m.generatedLocalMatchCount.toDouble()).toList(),
          ).toStringAsFixed(3),
          _spearman(
            members.map((m) => competitors[m.id]!.scores[method]).toList(),
            members.map((m) => competitors[m.id]!.windows
                .where((w) => w.kind != core.MatchKind.club)
                .length
                .toDouble()).toList(),
          ).toStringAsFixed(3),
          _spearman(
            members.map((m) => competitors[m.id]!.scores[method]).toList(),
            members.map((m) => competitors[m.id]!.meanFieldSize).toList(),
          ).toStringAsFixed(3),
        ],
    ],
  );

  print("\n========== Major-Exposure Classification AUC ==========");
  _printTable(
    ["Method", "Any Major", "Annual", "Frequent"],
    [
      for (var method in kMethodNames)
        [
          method,
          _auc(
            members.map((m) => competitors[m.id]!.scores[method]).toList(),
            members.map((m) => m.cohort != MajorCohort.localOnly).toList(),
          ).toStringAsFixed(3),
          _auc(
            members.map((m) => competitors[m.id]!.scores[method]).toList(),
            members.map((m) =>
                m.cohort == MajorCohort.annual ||
                m.cohort == MajorCohort.frequent).toList(),
          ).toStringAsFixed(3),
          _auc(
            members.map((m) => competitors[m.id]!.scores[method]).toList(),
            members.map((m) => m.cohort == MajorCohort.frequent).toList(),
          ).toStringAsFixed(3),
        ],
    ],
  );

  print("\n========== Active-Member Major-Exposure AUC ==========");
  print("Excludes roster members with no generated match entries.");
  _printTable(
    ["Method", "Any Major", "Annual", "Frequent"],
    [
      for (var method in kMethodNames)
        [
          method,
          _auc(
            activeMembers.map((m) => competitors[m.id]!.scores[method]).toList(),
            activeMembers.map((m) => m.cohort != MajorCohort.localOnly).toList(),
          ).toStringAsFixed(3),
          _auc(
            activeMembers.map((m) => competitors[m.id]!.scores[method]).toList(),
            activeMembers.map((m) =>
                m.cohort == MajorCohort.annual ||
                m.cohort == MajorCohort.frequent).toList(),
          ).toStringAsFixed(3),
          _auc(
            activeMembers.map((m) => competitors[m.id]!.scores[method]).toList(),
            activeMembers.map((m) => m.cohort == MajorCohort.frequent).toList(),
          ).toStringAsFixed(3),
        ],
    ],
  );

  print("\n========== Exact-Size Top-K Recovery ==========");
  print("Each percentage is precision and recall because K equals the known cohort size.");
  _printTable(
    ["Method", "Any @ 11,118", "Annual @ 3,761", "Frequent @ 2,244"],
    [
      for (var method in kMethodNames)
        [
          method,
          _topKRecovery(
            members,
            competitors,
            method,
            kAnyMajorCount,
            (m) => m.cohort != MajorCohort.localOnly,
          ).toStringAsFixed(1),
          _topKRecovery(
            members,
            competitors,
            method,
            kAnnualMajorCount,
            (m) =>
                m.cohort == MajorCohort.annual ||
                m.cohort == MajorCohort.frequent,
          ).toStringAsFixed(1),
          _topKRecovery(
            members,
            competitors,
            method,
            kFrequentMajorCount,
            (m) => m.cohort == MajorCohort.frequent,
          ).toStringAsFixed(1),
        ],
    ],
  );
}

List<String> _cohortActivityRow(
  List<MemberProfile> members,
  Map<int, core.Competitor> competitors,
) {
  return [
    members.first.cohort.name,
    "${members.length}",
    members.map((m) => m.generatedLocalMatchCount).average.toStringAsFixed(1),
    members.map((m) => m.generatedMajorMatchCount).average.toStringAsFixed(1),
    members.map((m) => m.generatedLocalClubs.length).average.toStringAsFixed(2),
    members.map((m) => competitors[m.id]!.windows
        .where((w) => w.kind != core.MatchKind.club)
        .length).average.toStringAsFixed(2),
  ];
}

List<String> _majorCountBandRow(
  String label,
  List<MemberProfile> members,
  Map<int, core.Competitor> competitors,
) {
  if (members.isEmpty) {
    return [label, "0", "-", "-", "-", "-", "-"];
  }
  return [
    label,
    "${members.length}",
    members.map((m) => m.generatedLocalMatchCount).average.toStringAsFixed(1),
    members.map((m) => m.generatedLocalClubs.length).average.toStringAsFixed(2),
    members.map((m) => competitors[m.id]!.scores.sqrt).average.toStringAsFixed(1),
    members.map((m) => competitors[m.id]!.scores.effective).average.toStringAsFixed(1),
    members.map((m) => competitors[m.id]!.scores.credit).average.toStringAsFixed(1),
  ];
}

List<String> _cohortMetricRow(
  List<MemberProfile> members,
  Map<int, core.Competitor> competitors,
) {
  var ratings = members.map((m) => competitors[m.id]!).toList();
  return [
    members.first.cohort.name,
    "${members.length}",
    ratings.map((c) => c.uniqueOpponentCount).average.toStringAsFixed(0),
    ratings.map((c) => c.totalOpponentCount).average.toStringAsFixed(0),
    ratings.map((c) => c.effectiveDegree).average.toStringAsFixed(1),
    ratings.map((c) => c.recentCoverageCredit).average.toStringAsFixed(1),
    ratings.map((c) => c.regionDiversity).average.toStringAsFixed(2),
    for (var method in kMethodNames)
      ratings.map((c) => c.scores[method]).average.toStringAsFixed(1),
  ];
}

List<String> _matchMetricRow(List<core.Match> matches) {
  if (matches.isEmpty) {
    return ["-", "0", "-", "-", "-", "-", for (var _ in kMethodNames) "-"];
  }
  return [
    matches.first.kind.name,
    "${matches.length}",
    matches.map((m) => m.competitorIds.length).average.toStringAsFixed(0),
    matches.map((m) => m.externalCoverage).average.toStringAsFixed(0),
    matches.map((m) => m.coverageEfficiency).average.toStringAsFixed(3),
    matches.map((m) => m.effectiveCarrierCount).average.toStringAsFixed(1),
    for (var method in kMethodNames)
      matches.map((m) => m.matchScores[method]).average.toStringAsFixed(1),
  ];
}

double _topKRecovery(
  List<MemberProfile> members,
  Map<int, core.Competitor> competitors,
  String method,
  int k,
  bool Function(MemberProfile) positive,
) {
  var sorted = [...members]
    ..sort((a, b) => competitors[b.id]!.scores[method]
        .compareTo(competitors[a.id]!.scores[method]));
  return sorted.take(k).where(positive).length / k * 100;
}

double _auc(List<double> scores, List<bool> positive) {
  var ranks = _ranks(scores);
  var positiveCount = positive.where((value) => value).length;
  var negativeCount = positive.length - positiveCount;
  if (positiveCount == 0 || negativeCount == 0) {
    return 0.5;
  }
  var positiveRankSum = 0.0;
  for (var i = 0; i < positive.length; i++) {
    if (positive[i]) {
      positiveRankSum += ranks[i] + 1;
    }
  }
  return (positiveRankSum - positiveCount * (positiveCount + 1) / 2) /
      (positiveCount * negativeCount);
}

double _spearman(List<double> a, List<double> b) {
  return _pearson(_ranks(a), _ranks(b));
}

List<double> _ranks(List<double> values) {
  var indexed = [for (var i = 0; i < values.length; i++) (i, values[i])]
    ..sort((a, b) => a.$2.compareTo(b.$2));
  var ranks = List<double>.filled(values.length, 0);
  var start = 0;
  while (start < indexed.length) {
    var end = start + 1;
    while (end < indexed.length && indexed[end].$2 == indexed[start].$2) {
      end++;
    }
    var rank = (start + end - 1) / 2.0;
    for (var i = start; i < end; i++) {
      ranks[indexed[i].$1] = rank;
    }
    start = end;
  }
  return ranks;
}

double _pearson(List<double> x, List<double> y) {
  var xMean = x.average;
  var yMean = y.average;
  var numerator = 0.0;
  var xDenominator = 0.0;
  var yDenominator = 0.0;
  for (var i = 0; i < x.length; i++) {
    var xDiff = x[i] - xMean;
    var yDiff = y[i] - yMean;
    numerator += xDiff * yDiff;
    xDenominator += xDiff * xDiff;
    yDenominator += yDiff * yDiff;
  }
  var denominator = sqrt(xDenominator * yDenominator);
  return denominator == 0 ? 0 : numerator / denominator;
}

void _printTable(List<String> headers, List<List<String>> rows) {
  var widths = List<int>.generate(headers.length, (column) {
    return [
      headers[column].length,
      ...rows.map((row) => row[column].length),
    ].max;
  });
  String format(List<String> cells) => [
    for (var i = 0; i < cells.length; i++)
      cells[i].padLeft(widths[i]),
  ].join("  ");

  print(format(headers));
  print([for (var width in widths) "-" * width].join("  "));
  for (var row in rows) {
    print(format(row));
  }
}
