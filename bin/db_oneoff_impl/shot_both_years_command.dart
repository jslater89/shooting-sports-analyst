/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

/// Per single-division L2s Main LLR group, count shooters with:
/// 1. ≥1 unique match in 2025–2026
/// 2. ≥1 unique match in each of 2025 and 2026
/// 3. ≥4 unique matches across 2025–2026 combined
///
/// Launch: dart run bin/db_oneoffs.dart SBY

import "package:collection/collection.dart";
import "package:dart_console/dart_console.dart";
import "package:shooting_sports_analyst/console/repl.dart";
import "package:shooting_sports_analyst/data/database/analyst_database.dart";
import "package:shooting_sports_analyst/data/database/match/rating_project_database.dart";
import "package:shooting_sports_analyst/data/database/schema/ratings.dart";

import "base.dart";

const String kDefaultLlrProjectName = "L2s Main LLR";
const int kYearA = 2025;
const int kYearB = 2026;
const int kMinMatchesOverTwoYears = 4;

class ShotBothYearsCommand extends DbOneoffCommand {
  ShotBothYearsCommand(AnalystDatabase db) : super(db);

  @override
  final String key = "SBY";

  @override
  final String title = "Shot in 2025 and 2026 (LLR)";

  @override
  String? get description =>
      "Per single-division L2s Main LLR group: ≥1 match in $kYearA–$kYearB, "
      "≥1 match per year, and ≥$kMinMatchesOverTwoYears matches over those two years.";

  @override
  Future<void> executor(Console console, List<MenuArgumentValue> arguments) async {
    await _run(db, console, projectName: kDefaultLlrProjectName);
  }
}

class _GroupCounts {
  _GroupCounts(this.group, this.ratings);

  final RatingGroup group;
  final List<DbShooterRating> ratings;
  int get rated => ratings.length;
  int anyTwoYears = 0;
  int bothYears = 0;
  int fourOverTwoYears = 0;
  final List<DbShooterRating> anyTwoYearRatings = [];
  final List<DbShooterRating> bothYearRatings = [];
  final List<DbShooterRating> fourOverTwoYearRatings = [];
}

Future<void> _run(
  AnalystDatabase db,
  Console console, {
  required String projectName,
}) async {
  final project = await db.getRatingProjectByName(projectName);
  if (project == null) {
    console.print("Rating project not found: $projectName");
    return;
  }

  if (!project.dbGroups.isLoaded) {
    await project.dbGroups.load();
  }

  final groups = project.groups
      .where((g) => g.divisionNames.length == 1)
      .sorted((a, b) => a.sortOrder.compareTo(b.sortOrder))
      .toList();
  if (groups.isEmpty) {
    console.print("No single-division groups in $projectName.");
    return;
  }

  final matchYearBySourceId = <String, int>{};
  var projectMatchesYearA = 0;
  var projectMatchesYearB = 0;
  for (final ptr in project.matchPointers) {
    final year = ptr.date?.year;
    if (year != kYearA && year != kYearB) {
      continue;
    }
    if (year == kYearA) {
      projectMatchesYearA++;
    }
    else {
      projectMatchesYearB++;
    }
    for (final id in ptr.sourceIds) {
      matchYearBySourceId[id] = year!;
    }
  }

  final rangeStart = DateTime(kYearA, 1, 1);
  final rangeEnd = DateTime(kYearB, 12, 31, 23, 59, 59);

  final groupCounts = <_GroupCounts>[];
  for (final group in groups) {
    final ratingsRes = project.getRatingsSync(group);
    if (ratingsRes.isErr()) {
      console.print("Skipping ${group.name}; failed to load ratings.");
      continue;
    }
    groupCounts.add(_GroupCounts(group, ratingsRes.unwrap()));
  }

  for (final counts in groupCounts) {
    console.print("${counts.group.name} (${counts.rated})");
    for (final rating in counts.ratings) {
      if (rating.lastSeen.isBefore(rangeStart) || rating.firstSeen.isAfter(rangeEnd)) {
        continue;
      }

      final events = db.getRatingEventsForSync(
        rating,
        after: rangeStart,
        before: rangeEnd,
      );
      final matchesYearA = <String>{};
      final matchesYearB = <String>{};
      for (final event in events) {
        final year = matchYearBySourceId[event.matchId];
        if (year == kYearA) {
          matchesYearA.add(event.matchId);
        }
        else if (year == kYearB) {
          matchesYearB.add(event.matchId);
        }
      }

      final matchCount = matchesYearA.length + matchesYearB.length;
      if (matchCount == 0) {
        continue;
      }

      counts.anyTwoYears++;
      counts.anyTwoYearRatings.add(rating);

      if (matchesYearA.isNotEmpty && matchesYearB.isNotEmpty) {
        counts.bothYears++;
        counts.bothYearRatings.add(rating);
      }
      if (matchCount >= kMinMatchesOverTwoYears) {
        counts.fourOverTwoYears++;
        counts.fourOverTwoYearRatings.add(rating);
      }
    }
  }

  const divW = 18;
  const colW = 10;
  String cell(String s, {int w = colW, bool left = false}) =>
      left ? s.padRight(w) : s.padLeft(w);

  final buf = StringBuffer();
  buf.writeln(
    "$projectName, single-division. "
    "Project matches: $projectMatchesYearA in $kYearA, $projectMatchesYearB in $kYearB.",
  );
  buf.writeln(
    "≥1/2yrs: any match in $kYearA–$kYearB. "
    "≥1/yr: ≥1 in each year. "
    "≥$kMinMatchesOverTwoYears/2yrs: ≥$kMinMatchesOverTwoYears unique matches across both years.",
  );
  buf.writeln("");
  buf.writeln(
    "${cell("Division", w: divW, left: true)}"
    "${cell("N")}"
    "${cell("≥1/2yrs")}"
    "${cell("≥1/yr")}"
    "${cell("≥$kMinMatchesOverTwoYears/2yrs")}",
  );
  buf.writeln("-" * (divW + colW * 4));

  var sumRated = 0;
  var sumAny = 0;
  var sumBoth = 0;
  var sumFour = 0;
  final allRated = <DbShooterRating>[];
  final allAny = <DbShooterRating>[];
  final allBoth = <DbShooterRating>[];
  final allFour = <DbShooterRating>[];

  for (final counts in groupCounts) {
    sumRated += counts.rated;
    sumAny += counts.anyTwoYears;
    sumBoth += counts.bothYears;
    sumFour += counts.fourOverTwoYears;
    allRated.addAll(counts.ratings);
    allAny.addAll(counts.anyTwoYearRatings);
    allBoth.addAll(counts.bothYearRatings);
    allFour.addAll(counts.fourOverTwoYearRatings);

    buf.writeln(
      "${cell(counts.group.name, w: divW, left: true)}"
      "${cell("${counts.rated}")}"
      "${cell("${counts.anyTwoYears}")}"
      "${cell("${counts.bothYears}")}"
      "${cell("${counts.fourOverTwoYears}")}",
    );
  }

  buf.writeln("-" * (divW + colW * 4));
  buf.writeln(
    "${cell("Sum (not unique)", w: divW, left: true)}"
    "${cell("$sumRated")}"
    "${cell("$sumAny")}"
    "${cell("$sumBoth")}"
    "${cell("$sumFour")}",
  );
  buf.writeln(
    "${cell("Unique people", w: divW, left: true)}"
    "${cell("${_uniquePeople(allRated)}")}"
    "${cell("${_uniquePeople(allAny)}")}"
    "${cell("${_uniquePeople(allBoth)}")}"
    "${cell("${_uniquePeople(allFour)}")}",
  );

  console.print("");
  console.print(buf.toString());
}

int _uniquePeople(List<DbShooterRating> ratings) {
  final parent = <String, String>{};

  String find(String x) {
    final p = parent[x];
    if (p == null || p == x) {
      return x;
    }
    final root = find(p);
    parent[x] = root;
    return root;
  }

  void union(String a, String b) {
    final ra = find(a);
    final rb = find(b);
    if (ra != rb) {
      parent[ra] = rb;
    }
  }

  var anonymous = 0;
  for (final rating in ratings) {
    final nums = [...rating.allPossibleMemberNumbers];
    if (nums.isEmpty) {
      if (rating.memberNumber.isNotEmpty) {
        nums.add(rating.memberNumber);
      }
      else {
        anonymous++;
        continue;
      }
    }
    for (final n in nums) {
      parent.putIfAbsent(n, () => n);
    }
    for (var i = 1; i < nums.length; i++) {
      union(nums.first, nums[i]);
    }
  }

  final roots = <String>{};
  for (final n in parent.keys) {
    roots.add(find(n));
  }
  return roots.length + anonymous;
}
