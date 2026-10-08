/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

/// Export USA Extreme Open 2024-2026 as MIFF and build a member-number review CSV.
///
/// Name lookup uses L2s Main LLR via the same exact deduplicator-name query as
/// search_shooters (FindShooterSearchMode.exact). A row is resolved when the
/// mapped rating group has exactly one person with that name, when exactly one
/// person with that name exists in any other group, or when the match already
/// has a USPSA-shaped member number.
///
///   dart run bin/extreme_open_member_lookup.dart [output-directory] [match name...]
import "dart:convert";
import "dart:io";

import "package:collection/collection.dart";
import "package:shooting_sports_analyst/api/miff/miff.dart";
import "package:shooting_sports_analyst/config/serialized_config.dart";
import "package:shooting_sports_analyst/data/database/analyst_database.dart";
import "package:shooting_sports_analyst/data/database/match/rating_project_database.dart";
import "package:shooting_sports_analyst/data/database/schema/ratings.dart";
import "package:shooting_sports_analyst/data/ranking/deduplication/shooter_deduplicator.dart";
import "package:shooting_sports_analyst/data/sport/match/match.dart";
import "package:shooting_sports_analyst/data/sport/shooter/shooter.dart";
import "package:shooting_sports_analyst/flutter_native_providers.dart";
import "package:shooting_sports_analyst/logger.dart";
import "package:shooting_sports_analyst/server/providers.dart";
import "package:shooting_sports_analyst/util.dart";

const String kProjectName = "L2s Main LLR";

const List<String> kMatchNames = [
  "USA Extreme Open 2024",
  "USA Extreme Open 2025",
  "USA Extreme Open 2026",
];

/// Entered division -> the one USPSA rating group from [ipscToUspsaLink].
/// PCC Iron has no link target, so those names are searched across all groups.
const Map<String, List<String>> kDivisionGroups = {
  "Carry Optics": ["Carry Optics"],
  "Limited": ["Limited"],
  "Open": ["Open"],
  "PCC": ["PCC"],
  "PCC Optic": ["PCC"],
  "Production": ["Production"],
  "Production Optics": ["Carry Optics"],
  "Optics": ["Limited Optics"],
  "Revolver": ["Revolver"],
  "Single Stack": ["Single Stack"],
  "Standard": ["Limited"],
  "Classic": ["Single Stack"],
};

/// A/TY/FY or F/TYF/FYF plus 4-6 digits, L plus 3-4, B plus 2-3, or RD1-RD25.
final RegExp _uspsaMemberNumber = RegExp(
  r"^(?:(?:TYF|FYF|TY|FY|A|F)\d{4,6}|L\d{3,4}|B\d{2,3}|RD(?:[1-9]|1\d|2[0-5]))$",
);

bool _looksLikeUspsaMemberNumber(String number) {
  return _uspsaMemberNumber.hasMatch(number.toUpperCase());
}

final _log = SSALogger("ExtremeOpenMembers");

Future<void> main(List<String> args) async {
  FlutterOrNative.debugModeProvider = ServerDebugProvider();
  FlutterOrNative.isolateModeProvider = ServerDebugProvider(isMultiIsolate: false);
  SSALogger.consoleOutput = false;
  SSALogger.fileOutput = true;
  await _log.ready;
  await ConfigLoader().readyFuture;

  final outDir = Directory(args.isEmpty ? "research/usa-extreme-open" : args[0]);
  final matchNames = args.length > 1 ? args.sublist(1) : kMatchNames;
  final miffDir = Directory("${outDir.path}/miff");
  if (!miffDir.existsSync()) {
    miffDir.createSync(recursive: true);
  }

  final db = await AnalystDatabase();
  await db.ready;

  final project = await db.getRatingProjectByName(kProjectName);
  if (project == null) {
    stderr.writeln("Rating project not found: $kProjectName");
    exit(1);
  }
  if (!project.dbGroups.isLoaded) {
    await project.dbGroups.load();
  }
  final groupsByName = {for (final group in project.groups) group.name: group};

  final matches = await db.getMatchesByExactNames(matchNames);
  if (matches.length != matchNames.length) {
    final found = matches.map((m) => m.eventName).toSet();
    stderr.writeln("Expected ${matchNames.length} matches, found ${matches.length}: $found");
    exit(1);
  }
  matches.sort((a, b) => a.eventName.compareTo(b.eventName));

  final exporter = MiffExporter();
  final rows = <ReviewRow>[];
  final cache = <String, List<DbShooterRating>>{};

  for (final dbMatch in matches) {
    final hydratedRes = dbMatch.hydrateSync();
    if (hydratedRes.isErr()) {
      stderr.writeln("Hydrate failed for ${dbMatch.eventName}: ${hydratedRes.unwrapErr()}");
      exit(1);
    }
    final match = hydratedRes.unwrap();
    final miffRes = exporter.exportMatch(match);
    if (miffRes.isErr()) {
      stderr.writeln("Export failed for ${match.name}: ${miffRes.unwrapErr()}");
      exit(1);
    }
    final sourceId = dbMatch.sourceIds.isEmpty ? "unknown" : dbMatch.sourceIds.first;
    final miffFile = File("${miffDir.path}/${match.name.safeFilename(replacement: "_")}-$sourceId.miff.gz");
    await miffFile.writeAsBytes(miffRes.unwrap());
    stdout.writeln("Exported ${match.name} (${match.shooters.length} shooters) -> ${miffFile.path}");

    for (final shooter in match.shooters) {
      rows.add(await _lookupShooter(
        db: db,
        project: project,
        groupsByName: groupsByName,
        cache: cache,
        match: match,
        shooter: shooter,
      ));
    }
  }

  rows.sort((a, b) {
    final byResolved = a.resolved == b.resolved ? 0 : (a.resolved ? 1 : -1);
    if (byResolved != 0) {
      return byResolved;
    }
    final byStatus = a.statusRank.compareTo(b.statusRank);
    if (byStatus != 0) {
      return byStatus;
    }
    final byMatch = a.matchName.compareTo(b.matchName);
    if (byMatch != 0) {
      return byMatch;
    }
    final byDivision = a.division.compareTo(b.division);
    if (byDivision != 0) {
      return byDivision;
    }
    return a.name.compareTo(b.name);
  });

  final maxPeople = rows.fold<int>(1, (max, row) => row.people.length > max ? row.people.length : max);
  final csv = StringBuffer();
  csv.writeln([
    "status",
    "match",
    "division",
    "name",
    "existingMemberNumber",
    for (var i = 1; i <= maxPeople; i++) i == 1 ? "memberNumber" : "memberNumber$i",
    "alsoKnown",
    "foundIn",
    "candidates",
    "note",
    "entryId",
    "sourceId",
    "dq",
    "reentry",
  ].map(_csv).join(","));
  for (final row in rows) {
    csv.writeln(row.toCsv(maxPeople));
  }

  final csvFile = File("${outDir.path}/member-number-review.csv");
  await csvFile.writeAsString(csv.toString());

  final jsonFile = File("${outDir.path}/member-number-lookup.json");
  await jsonFile.writeAsString(const JsonEncoder.withIndent("  ").convert({
    "project": kProjectName,
    "divisionGroups": kDivisionGroups,
    "rows": rows.map((r) => r.toJson()).toList(),
  }));

  final counts = <String, int>{};
  for (final row in rows) {
    counts[row.status] = (counts[row.status] ?? 0) + 1;
  }
  stdout.writeln("Wrote ${rows.length} rows to ${csvFile.path}");
  stdout.writeln("Lookup JSON: ${jsonFile.path}");
  for (final entry in counts.entries.sorted((a, b) => a.key.compareTo(b.key))) {
    stdout.writeln("  ${entry.key}: ${entry.value}");
  }
}

Future<ReviewRow> _lookupShooter({
  required AnalystDatabase db,
  required DbRatingProject project,
  required Map<String, RatingGroup> groupsByName,
  required Map<String, List<DbShooterRating>> cache,
  required ShootingMatch match,
  required MatchEntry shooter,
}) async {
  final division = shooter.division?.name ?? "";
  final name = "${shooter.firstName} ${shooter.lastName}".replaceAll(RegExp(r"\s+"), " ").trim();
  final tokens = name.split(" ").where((t) => t.isNotEmpty).toList();
  final mappedNames = kDivisionGroups[division] ?? const <String>[];
  final mappedGroups = mappedNames.map((n) => groupsByName[n]).whereType<RatingGroup>().toList();
  final otherGroups = project.groups.where((g) => !mappedGroups.any((m) => m.uuid == g.uuid)).toList();

  final exactMapped = await _exactPeople(db, project, cache, name, mappedGroups);
  late String status;
  late List<_Person> people;
  var candidates = "";

  if (exactMapped.length == 1) {
    status = "unique";
    people = exactMapped;
  }
  else if (exactMapped.length > 1) {
    status = "ambiguous";
    people = exactMapped;
  }
  else {
    final middleName = tokens.length >= 3 ? "${tokens.first} ${tokens.last}" : null;
    final swapped = tokens.length == 2 ? "${tokens.last} ${tokens.first}" : null;
    final middleHits = middleName == null
        ? const <_Person>[]
        : await _exactPeople(db, project, cache, middleName, mappedGroups);
    final swappedHits = swapped == null || swapped == name
        ? const <_Person>[]
        : await _exactPeople(db, project, cache, swapped, mappedGroups);

    if (middleHits.length == 1) {
      status = "dropped-middle";
      people = middleHits;
    }
    else if (middleHits.length > 1) {
      status = "ambiguous";
      people = middleHits;
    }
    else if (swappedHits.length == 1) {
      status = "swapped-name";
      people = swappedHits;
    }
    else if (swappedHits.length > 1) {
      status = "ambiguous";
      people = swappedHits;
    }
    else {
      final elsewhere = await _exactPeople(db, project, cache, name, otherGroups);
      if (elsewhere.length == 1) {
        status = "other-division";
        people = elsewhere;
      }
      else if (elsewhere.length > 1) {
        status = "ambiguous";
        people = elsewhere;
      }
      else {
        status = "missing";
        people = const [];
        final candidateGroups = mappedGroups.isEmpty ? project.groups : mappedGroups;
        if (tokens.isNotEmpty) {
          candidates = await _lastNameCandidates(db, project, cache, tokens, candidateGroups);
        }
      }
    }
  }

  var note = "";
  final existing = shooter.memberNumber;
  if (_looksLikeUspsaMemberNumber(existing)) {
    final agreeing = people.where((p) => p.numbers.contains(existing) || p.memberNumber == existing).toList();
    if (agreeing.isEmpty && people.isNotEmpty) {
      note = people.map((p) => "${p.displayName} ${p.memberNumber} (${p.groups.join("/")})").join("; ");
    }
    final known = agreeing.length == 1 ? agreeing.first.numbers : <String>{existing};
    final groups = agreeing.length == 1 ? agreeing.first.groups : <String>{};
    people = [
      _Person(
        displayName: name,
        memberNumber: existing,
        numbers: {...known, existing},
        groups: groups,
      ),
    ];
    status = "existing-uspsa";
    candidates = "";
  }
  else if (mappedGroups.isEmpty && status == "other-division") {
    note = "No IPSC division link; one name match in another group";
  }

  return ReviewRow(
    status: status,
    matchName: match.name,
    division: division,
    name: name,
    existingMemberNumber: existing,
    people: people,
    candidates: candidates,
    note: note,
    entryId: shooter.entryId,
    sourceId: shooter.sourceId ?? "",
    dq: shooter.dq,
    reentry: shooter.reentry,
  );
}

Future<List<_Person>> _exactPeople(
  AnalystDatabase db,
  DbRatingProject project,
  Map<String, List<DbShooterRating>> cache,
  String name,
  List<RatingGroup> groups,
) async {
  final hits = <_Hit>[];
  for (final group in groups) {
    final ratings = await _cached(
      db,
      project,
      cache,
      group,
      name,
      FindShooterSearchMode.exact,
      50,
    );
    for (final rating in ratings) {
      hits.add(_Hit(group.name, rating));
    }
  }
  return _cluster(hits);
}

Future<String> _lastNameCandidates(
  AnalystDatabase db,
  DbRatingProject project,
  Map<String, List<DbShooterRating>> cache,
  List<String> tokens,
  List<RatingGroup> groups,
) async {
  final first = ShooterDeduplicator.processNameString(tokens.first);
  final last = ShooterDeduplicator.processNameString(tokens.last);
  if (last.length < 2) {
    return "";
  }
  final hits = <_Hit>[];
  for (final group in groups) {
    final ratings = await _cached(
      db,
      project,
      cache,
      group,
      tokens.last,
      FindShooterSearchMode.contains,
      80,
    );
    for (final rating in ratings) {
      final ratingTokens = "${rating.firstName} ${rating.lastName}"
          .replaceAll(RegExp(r"\s+"), " ")
          .trim()
          .split(" ");
      if (ratingTokens.isEmpty) {
        continue;
      }
      final ratingLast = ShooterDeduplicator.processNameString(ratingTokens.last);
      final ratingFirst = ShooterDeduplicator.processNameString(ratingTokens.first);
      if (ratingLast != last) {
        continue;
      }
      final firstClose = ratingFirst == first
          || (first.length >= 3 && (ratingFirst.startsWith(first) || first.startsWith(ratingFirst)));
      if (!firstClose) {
        continue;
      }
      hits.add(_Hit(group.name, rating));
    }
  }
  final people = _cluster(hits);
  return people.map((p) => "${p.displayName} ${p.memberNumber} (${p.groups.join("/")})").join("; ");
}

Future<List<DbShooterRating>> _cached(
  AnalystDatabase db,
  DbRatingProject project,
  Map<String, List<DbShooterRating>> cache,
  RatingGroup group,
  String name,
  FindShooterSearchMode mode,
  int limit,
) async {
  final key = "${group.uuid}|${mode.name}|${ShooterDeduplicator.processNameString(name)}|$limit";
  final existing = cache[key];
  if (existing != null) {
    return existing;
  }
  final ratings = await db.findShooterRatings(
    project: project,
    group: group,
    name: name,
    searchMode: mode,
    limit: limit,
  );
  cache[key] = ratings;
  return ratings;
}

List<_Person> _cluster(List<_Hit> hits) {
  final people = <_Person>[];
  for (final hit in hits) {
    final numbers = {...hit.rating.allPossibleMemberNumbers, hit.rating.memberNumber}
      ..removeWhere((n) => n.isEmpty);
    final overlapping = people.where((p) => p.numbers.intersection(numbers).isNotEmpty).toList();
    if (overlapping.isEmpty) {
      people.add(_Person(
        displayName: "${hit.rating.firstName} ${hit.rating.lastName}".replaceAll(RegExp(r"\s+"), " ").trim(),
        memberNumber: hit.rating.memberNumber,
        numbers: numbers,
        groups: {hit.groupName},
      ));
    }
    else {
      final keep = overlapping.first;
      keep.numbers.addAll(numbers);
      keep.groups.add(hit.groupName);
      if (keep.memberNumber.isEmpty) {
        keep.memberNumber = hit.rating.memberNumber;
      }
      for (final extra in overlapping.skip(1)) {
        keep.numbers.addAll(extra.numbers);
        keep.groups.addAll(extra.groups);
        people.remove(extra);
      }
    }
  }
  people.sort((a, b) => a.memberNumber.compareTo(b.memberNumber));
  return people;
}

class _Hit {
  final String groupName;
  final DbShooterRating rating;
  _Hit(this.groupName, this.rating);
}

class _Person {
  String displayName;
  String memberNumber;
  final Set<String> numbers;
  final Set<String> groups;
  _Person({
    required this.displayName,
    required this.memberNumber,
    required this.numbers,
    required this.groups,
  });

  String get alsoKnown {
    final extras = [...numbers.where((n) => n != memberNumber)]..sort();
    return extras.join(" ");
  }
}

class ReviewRow {
  final String status;
  final String matchName;
  final String division;
  final String name;
  final String existingMemberNumber;
  final List<_Person> people;
  final String candidates;
  final String note;
  final int entryId;
  final String sourceId;
  final bool dq;
  final bool reentry;

  ReviewRow({
    required this.status,
    required this.matchName,
    required this.division,
    required this.name,
    required this.existingMemberNumber,
    required this.people,
    required this.candidates,
    required this.note,
    required this.entryId,
    required this.sourceId,
    required this.dq,
    required this.reentry,
  });

  bool get resolved => status == "unique" || status == "other-division" || status == "existing-uspsa";

  int get statusRank {
    switch (status) {
      case "missing":
        return 0;
      case "ambiguous":
        return 1;
      case "swapped-name":
        return 2;
      case "dropped-middle":
        return 3;
      case "other-division":
        return 4;
      case "unique":
        return 5;
      case "existing-uspsa":
        return 6;
      default:
        return 7;
    }
  }

  String toCsv(int maxPeople) {
    final numbers = [
      for (final person in people) person.memberNumber,
      for (var i = people.length; i < maxPeople; i++) "",
    ];
    return [
      status,
      matchName,
      division,
      name,
      existingMemberNumber,
      ...numbers,
      people.map((p) => p.alsoKnown).where((s) => s.isNotEmpty).join(" | "),
      people.map((p) => p.groups.join("/")).join(" | "),
      candidates,
      note,
      "$entryId",
      sourceId,
      dq ? "yes" : "",
      reentry ? "yes" : "",
    ].map(_csv).join(",");
  }

  Map<String, Object?> toJson() {
    return {
      "status": status,
      "match": matchName,
      "division": division,
      "name": name,
      "existingMemberNumber": existingMemberNumber,
      "memberNumbers": people.map((p) => p.memberNumber).toList(),
      "alsoKnown": people.map((p) => p.numbers.toList()..sort()).toList(),
      "foundIn": people.map((p) => p.groups.toList()..sort()).toList(),
      "candidates": candidates,
      "note": note,
      "entryId": entryId,
      "sourceId": sourceId,
      "dq": dq,
      "reentry": reentry,
    };
  }
}

String _csv(String value) {
  if (value.contains(",") || value.contains("\"") || value.contains("\n")) {
    return "\"${value.replaceAll("\"", "\"\"")}\"";
  }
  return value;
}
