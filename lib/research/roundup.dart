/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

part of "research_facade.dart";

const int _kPackageFinishCap = 20;

ResearchError? _checkHeatArgs({
  required bool includeRatings,
  required int heatPercentile,
  required int heatMinCount,
  required int ratingMinMatches,
}) {
  if (!includeRatings) {
    return null;
  }
  if (heatPercentile < 0 || heatPercentile > 100) {
    return ResearchError("heatPercentile must be 0-100");
  }
  if (heatMinCount < 1) {
    return ResearchError("heatMinCount must be >= 1");
  }
  if (ratingMinMatches < 0) {
    return ResearchError("ratingMinMatches must be >= 0");
  }
  return null;
}

bool _sameCalendarDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

double _percentileRank(List<double> sortedAsc, double value) {
  if (sortedAsc.isEmpty) {
    return 0;
  }
  var lo = 0;
  var hi = sortedAsc.length;
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    if (sortedAsc[mid] <= value) {
      lo = mid + 1;
    }
    else {
      hi = mid;
    }
  }
  return 100.0 * lo / sortedAsc.length;
}

double _percentileValue(List<double> sortedAsc, int percentile) {
  if (sortedAsc.isEmpty) {
    return 0;
  }
  final t = percentile.clamp(0, 100) / 100.0;
  final idx = ((sortedAsc.length - 1) * t).round().clamp(0, sortedAsc.length - 1);
  return sortedAsc[idx];
}

class _ScorePool {
  _ScorePool({
    required this.label,
    required this.kind,
    required this.scores,
    required this.group,
  });

  final String label;
  final String kind;
  final Map<MatchEntry, RelativeMatchScore> scores;
  final RatingGroup? group;
}

class _FinisherRating {
  _FinisherRating({
    required this.preMatchRating,
    required this.ratingPct,
    required this.groupUuid,
    required this.groupName,
    required this.p90Rating,
    required this.p95Rating,
  });

  final double preMatchRating;
  final double ratingPct;
  final String groupUuid;
  final String groupName;
  final double p90Rating;
  final double p95Rating;
}

class _HeatContext {
  _HeatContext(this.ratings);

  final Map<MatchEntry, _FinisherRating> ratings;
}

class _FieldMember {
  _FieldMember({
    required this.rating,
    required this.scaledRating,
    required this.lastChange,
    required this.trend,
    required this.matchCount,
  });

  final ShooterRating rating;
  final double scaledRating;
  final double lastChange;
  final double trend;
  final int matchCount;
  double ratingPct = 0;
  double lastChangePct = 0;
  double trendPct = 0;
}

Future<ResearchResult<PackageMoversResponse>> computePackageMovers(
  ResearchFacade facade, {
  required String? projectName,
  required String? groupUuid,
  required String? groupName,
  required List<String>? groupNames,
  required DateTime since,
  required DateTime? seenSince,
  required int minMatches,
  required String direction,
  required int? minRatingPct,
  required int? signalPct,
  required String signalBasis,
  required int limit,
}) async {
  if (limit < 1) {
    return Result.err(ResearchError("limit must be >= 1"));
  }
  if (minMatches < 0) {
    return Result.err(ResearchError("minMatches must be >= 0"));
  }
  if (minRatingPct != null && (minRatingPct < 0 || minRatingPct > 100)) {
    return Result.err(ResearchError("minRatingPct must be 0-100"));
  }
  if (signalPct != null && (signalPct < 0 || signalPct > 100)) {
    return Result.err(ResearchError("signalPct must be 0-100"));
  }
  final directionNorm = direction.trim().toLowerCase();
  if (directionNorm != "up" && directionNorm != "down" && directionNorm != "both") {
    return Result.err(ResearchError("direction must be up, down, or both"));
  }
  final basis = signalBasis.trim().toLowerCase();
  if (basis != "package" && basis != "active") {
    return Result.err(ResearchError("signalBasis must be package or active"));
  }

  final projectRes = await facade._requireProject(projectName ?? kDefaultResearchProjectName);
  if (projectRes.isErr()) {
    return Result.errFrom(projectRes);
  }
  final project = projectRes.unwrap();
  if (!project.dbGroups.isLoaded) {
    await project.dbGroups.load();
  }
  final groupsRes = await _packageGroups(
    facade,
    project,
    groupUuid: groupUuid,
    groupName: groupName,
    groupNames: groupNames,
  );
  if (groupsRes.isErr()) {
    return Result.errFrom(groupsRes);
  }
  final latestRes = facade._latestMatchDate(project);
  if (latestRes.isErr()) {
    return Result.errFrom(latestRes);
  }
  final latestMatchDate = latestRes.unwrap();
  final effectiveSeenSince = seenSince ?? DateTime(latestMatchDate.year - 1, 1, 1);

  final groups = <PackageMoverGroupDto>[];
  for (final group in groupsRes.unwrap()) {
    final built = await _packageGroup(
      facade,
      project: project,
      group: group,
      since: since,
      seenSince: effectiveSeenSince,
      minMatches: minMatches,
      direction: directionNorm,
      minRatingPct: minRatingPct,
      signalPct: signalPct,
      signalBasis: basis,
      limit: limit,
    );
    if (built.isErr()) {
      return Result.errFrom(built);
    }
    groups.add(built.unwrap());
  }

  return Result.ok(PackageMoversResponse(
    projectName: project.name,
    since: since,
    seenSince: effectiveSeenSince,
    latestMatchDate: latestMatchDate,
    direction: directionNorm,
    minMatches: minMatches,
    minRatingPct: minRatingPct,
    signalPct: signalPct,
    signalBasis: basis,
    groups: groups,
  ));
}

Future<ResearchResult<List<RatingGroup>>> _packageGroups(
  ResearchFacade facade,
  DbRatingProject project, {
  required String? groupUuid,
  required String? groupName,
  required List<String>? groupNames,
}) async {
  final seen = <String>{};
  final out = <RatingGroup>[];
  void addAll(List<RatingGroup> groups) {
    for (final group in groups) {
      if (seen.add(group.uuid)) {
        out.add(group);
      }
    }
  }

  final hasSingle = (groupUuid != null && groupUuid.isNotEmpty)
      || (groupName != null && groupName.trim().isNotEmpty);
  if (hasSingle) {
    final res = facade._resolveGroups(project, groupUuid: groupUuid, groupName: groupName);
    if (res.isErr()) {
      return Result.errFrom(res);
    }
    addAll(res.unwrap());
  }
  for (final raw in groupNames ?? const <String>[]) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    final res = facade._resolveGroups(project, groupName: trimmed);
    if (res.isErr()) {
      return Result.errFrom(res);
    }
    addAll(res.unwrap());
  }
  if (out.isEmpty) {
    return Result.err(ResearchError("Pass group, groupUuid, or groups"));
  }
  return Result.ok(out);
}

Future<ResearchResult<PackageMoverGroupDto>> _packageGroup(
  ResearchFacade facade, {
  required DbRatingProject project,
  required RatingGroup group,
  required DateTime since,
  required DateTime seenSince,
  required int minMatches,
  required String direction,
  required int? minRatingPct,
  required int? signalPct,
  required String signalBasis,
  required int limit,
}) async {
  final ratingsRes = await project.getRatings(group);
  if (ratingsRes.isErr()) {
    return Result.err(ResearchError(
      "Failed to load ratings for group ${group.name}: ${ratingsRes.unwrapErr()}",
      statusCode: 500,
    ));
  }
  final algo = project.settings.algorithm;
  final members = <_FieldMember>[];
  for (final dbRating in ratingsRes.unwrap()) {
    if (dbRating.lastSeen.isBefore(seenSince)) {
      continue;
    }
    final wrapped = project.wrapDbRatingSync(dbRating);
    final matches = wrapped.matchCount ?? wrapped.length;
    if (matches < minMatches) {
      continue;
    }
    members.add(_FieldMember(
      rating: wrapped,
      scaledRating: wrapped.scaledRating,
      lastChange: _safeScaledChange(facade, algo, wrapped.lastMatchChange),
      trend: _safeScaledChange(facade, algo, wrapped.trend.toDouble()),
      matchCount: matches,
    ));
  }

  final ratingValues = members.map((m) => m.scaledRating).toList()..sort();
  for (final member in members) {
    member.ratingPct = _percentileRank(ratingValues, member.scaledRating);
  }

  final package = members.where((m) => !m.rating.lastSeen.isBefore(since)).toList();
  final signalMembers = signalBasis == "active" ? members : package;
  final changeValues = signalMembers.map((m) => m.lastChange).toList()..sort();
  final trendValues = signalMembers.map((m) => m.trend).toList()..sort();
  for (final member in signalMembers) {
    member.lastChangePct = _percentileRank(changeValues, member.lastChange);
    member.trendPct = _percentileRank(trendValues, member.trend);
  }
  final matched = <({_FieldMember member, double score})>[];
  for (final member in package) {
    if (minRatingPct != null && member.ratingPct < minRatingPct) {
      continue;
    }
    final up = _upSignal(member);
    final down = _downSignal(member);
    final double score;
    if (direction == "up") {
      score = up;
    }
    else if (direction == "down") {
      score = down;
    }
    else {
      score = up >= down ? up : down;
    }
    if (score <= 0) {
      continue;
    }
    if (signalPct != null && score < signalPct) {
      continue;
    }
    matched.add((member: member, score: score));
  }
  matched.sort((a, b) {
    final byScore = b.score.compareTo(a.score);
    if (byScore != 0) {
      return byScore;
    }
    return b.member.scaledRating.compareTo(a.member.scaledRating);
  });

  final entries = <PackageMoverDto>[];
  for (final row in matched.take(limit)) {
    entries.add(await _moverRow(facade, algo, row.member, since));
  }

  return Result.ok(PackageMoverGroupDto(
    groupUuid: group.uuid,
    groupName: group.name,
    fieldSize: members.length,
    packageSize: package.length,
    matchedCount: matched.length,
    p90Rating: _percentileValue(ratingValues, 90),
    p95Rating: _percentileValue(ratingValues, 95),
    p10LastChange: _percentileValue(changeValues, 10),
    p90LastChange: _percentileValue(changeValues, 90),
    p10Trend: _percentileValue(trendValues, 10),
    p90Trend: _percentileValue(trendValues, 90),
    entries: entries,
  ));
}

double _safeScaledChange(ResearchFacade facade, RatingSystem algo, double change) {
  try {
    return facade._scaleChange(algo, change);
  } catch (_) {
    return 0;
  }
}

double _upSignal(_FieldMember member) {
  var score = 0.0;
  if (member.lastChange > 0 && member.lastChangePct > score) {
    score = member.lastChangePct;
  }
  if (member.trend > 0 && member.trendPct > score) {
    score = member.trendPct;
  }
  return score;
}

double _downSignal(_FieldMember member) {
  var score = 0.0;
  if (member.lastChange < 0) {
    final tail = 100 - member.lastChangePct;
    if (tail > score) {
      score = tail;
    }
  }
  if (member.trend < 0) {
    final tail = 100 - member.trendPct;
    if (tail > score) {
      score = tail;
    }
  }
  return score;
}

Future<PackageMoverDto> _moverRow(
  ResearchFacade facade,
  RatingSystem algo,
  _FieldMember member,
  DateTime since,
) async {
  final rawBefore = await _rawRatingBefore(facade, member.rating.wrappedRating, since, member.rating.rating);
  final preRating = algo.scaleRating(rawBefore);
  final finishes = await _packageFinishes(facade, member.rating.wrappedRating, since);
  return PackageMoverDto(
    ratingId: member.rating.wrappedRating.id,
    name: "${member.rating.firstName} ${member.rating.lastName}".trim(),
    memberNumber: member.rating.memberNumber,
    rating: member.scaledRating,
    preRating: preRating,
    ratingPct: member.ratingPct,
    lastChange: member.lastChange,
    lastChangePct: member.lastChangePct,
    trend: member.trend,
    trendPct: member.trendPct,
    packageChange: member.scaledRating - preRating,
    matchCount: member.matchCount,
    packageFinishes: finishes,
  );
}

Future<double> _rawRatingBefore(
  ResearchFacade facade,
  DbShooterRating rating,
  DateTime date,
  double fallback,
) async {
  final onOrAfter = await facade.db.getRatingEventsFor(
    rating,
    after: date,
    order: Order.ascending,
    limit: 40,
  );
  for (final event in onOrAfter) {
    if (_sameCalendarDay(event.date, date)) {
      return event.oldRating;
    }
    break;
  }
  final prior = await facade.db.getRatingEventsFor(rating, before: date, limit: 200);
  for (final event in prior) {
    if (_sameCalendarDay(event.date, date)) {
      continue;
    }
    return event.newRating;
  }
  return fallback;
}

Future<List<PackageFinishDto>> _packageFinishes(
  ResearchFacade facade,
  DbShooterRating rating,
  DateTime since,
) async {
  final events = await facade.db.getRatingEventsFor(rating, after: since);
  final seen = <String>{};
  final out = <PackageFinishDto>[];
  final fieldSizes = <String, int>{};
  for (final event in events) {
    if (event.stageNumber >= 0 || !seen.add(event.matchId)) {
      continue;
    }
    var matchName = event.matchId;
    final match = await event.getMatch(save: false);
    if (match != null) {
      matchName = match.eventName;
    }
    final entry = await _matchEntry(match, event.entryId);
    final info = await facade._entryDivisionAndClassification(match, event.entryId);
    int? fieldSize;
    final rawDivision = entry?.divisionName;
    if (match != null && rawDivision != null) {
      final key = "${match.id}|$rawDivision";
      final cached = fieldSizes[key];
      if (cached != null) {
        fieldSize = cached;
      }
      else {
        fieldSize = _divisionFieldSize(match, rawDivision);
        fieldSizes[key] = fieldSize;
      }
    }
    final score = event.canonicalMatchScore ?? event.matchScore;
    out.add(PackageFinishDto(
      matchId: event.matchId,
      matchName: matchName,
      date: event.date,
      division: info.division,
      place: score.place,
      fieldSize: fieldSize,
      pct: score.percentage,
    ));
    if (out.length >= _kPackageFinishCap) {
      break;
    }
  }
  return out;
}

Future<DbMatchEntryBase?> _matchEntry(DbShootingMatch? match, int entryId) async {
  if (match == null) {
    return null;
  }
  if (match.shootersStoredSeparately) {
    if (!match.shooterLinks.isLoaded) {
      await match.shooterLinks.load();
    }
    return match.shooterLinks.firstWhereOrNull((e) => e.entryId == entryId);
  }
  return match.shooters.firstWhereOrNull((e) => e.entryId == entryId);
}

int _divisionFieldSize(DbShootingMatch match, String divisionName) {
  final shooters = match.shootersStoredSeparately
      ? match.shooterLinks.toList()
      : match.shooters;
  return shooters.where((s) => !s.reentry && s.divisionName == divisionName).length;
}

Future<ResearchResult<_HeatContext>> loadHeatContext(
  ResearchFacade facade, {
  required ShootingMatch match,
  required List<_ScorePool> pools,
  required String projectName,
  required int minMatches,
  required DateTime? seenSince,
}) async {
  final projectRes = await facade._requireProject(projectName);
  if (projectRes.isErr()) {
    return Result.errFrom(projectRes);
  }
  final project = projectRes.unwrap();
  if (!project.dbGroups.isLoaded) {
    await project.dbGroups.load();
  }
  final latestRes = facade._latestMatchDate(project);
  if (latestRes.isErr()) {
    return Result.errFrom(latestRes);
  }
  final effectiveSeenSince = seenSince ?? DateTime(latestRes.unwrap().year - 1, 1, 1);
  final algo = project.settings.algorithm;
  final groups = [...project.groups];
  final cutoffs = <String, _GroupCutoff>{};
  final ratings = <MatchEntry, _FinisherRating>{};
  final lookupCache = <String, DbShooterRating?>{};

  Future<_GroupCutoff?> cutoffFor(RatingGroup group) async {
    final cached = cutoffs[group.uuid];
    if (cached != null) {
      return cached;
    }
    final loaded = await _groupCutoff(
      facade,
      project: project,
      group: group,
      seenSince: effectiveSeenSince,
      minMatches: minMatches,
    );
    if (loaded == null) {
      return null;
    }
    cutoffs[group.uuid] = loaded;
    return loaded;
  }

  for (final pool in pools) {
    for (final shooter in pool.scores.keys) {
      if (shooter.reentry) {
        continue;
      }
      final group = pool.group ?? _mostSpecificGroup(groups, shooter.division);
      if (group == null) {
        continue;
      }
      final cutoff = await cutoffFor(group);
      if (cutoff == null) {
        continue;
      }
      final dbRating = await _ratingForShooter(
        facade,
        project: project,
        group: group,
        shooter: shooter,
        cache: lookupCache,
      );
      if (dbRating == null) {
        continue;
      }
      final raw = await _rawRatingBeforeMatch(facade, dbRating, match);
      if (raw == null) {
        continue;
      }
      final scaled = algo.scaleRating(raw);
      ratings[shooter] = _FinisherRating(
        preMatchRating: scaled,
        ratingPct: _percentileRank(cutoff.sortedRatings, scaled),
        groupUuid: group.uuid,
        groupName: group.name,
        p90Rating: cutoff.p90,
        p95Rating: cutoff.p95,
      );
    }
  }
  return Result.ok(_HeatContext(ratings));
}

class _GroupCutoff {
  _GroupCutoff({
    required this.sortedRatings,
    required this.p90,
    required this.p95,
  });

  final List<double> sortedRatings;
  final double p90;
  final double p95;
}

Future<_GroupCutoff?> _groupCutoff(
  ResearchFacade facade, {
  required DbRatingProject project,
  required RatingGroup group,
  required DateTime seenSince,
  required int minMatches,
}) async {
  final ratingsRes = await project.getRatings(group);
  if (ratingsRes.isErr()) {
    return null;
  }
  final values = <double>[];
  for (final dbRating in ratingsRes.unwrap()) {
    if (dbRating.lastSeen.isBefore(seenSince)) {
      continue;
    }
    final wrapped = project.wrapDbRatingSync(dbRating);
    final matches = wrapped.matchCount ?? wrapped.length;
    if (matches < minMatches) {
      continue;
    }
    values.add(wrapped.scaledRating);
  }
  values.sort();
  return _GroupCutoff(
    sortedRatings: values,
    p90: _percentileValue(values, 90),
    p95: _percentileValue(values, 95),
  );
}

RatingGroup? _mostSpecificGroup(List<RatingGroup> groups, Division? division) {
  if (division == null) {
    return null;
  }
  final hits = groups.where((g) => g.containsDivision(division)).toList();
  if (hits.isEmpty) {
    return null;
  }
  hits.sort((a, b) {
    final byCount = a.divisionNames.length.compareTo(b.divisionNames.length);
    if (byCount != 0) {
      return byCount;
    }
    return a.sortOrder.compareTo(b.sortOrder);
  });
  return hits.first;
}

Future<DbShooterRating?> _ratingForShooter(
  ResearchFacade facade, {
  required DbRatingProject project,
  required RatingGroup group,
  required MatchEntry shooter,
  required Map<String, DbShooterRating?> cache,
}) async {
  final mn = facade._processedMemberNumber(project, shooter.memberNumber);
  final key = "${group.uuid}|$mn|${shooter.firstName}|${shooter.lastName}";
  if (cache.containsKey(key)) {
    return cache[key];
  }
  DbShooterRating? rating;
  if (mn.isNotEmpty) {
    rating = await facade.db.maybeKnownShooter(
      project: project,
      group: group,
      memberNumber: mn,
      usePossibleMemberNumbers: true,
    );
  }
  if (rating == null) {
    final name = "${shooter.firstName} ${shooter.lastName}".trim();
    if (name.length >= 2) {
      final exact = await facade.db.findShooterRatings(
        project: project,
        group: group,
        name: name,
        searchMode: FindShooterSearchMode.exact,
        limit: 2,
      );
      if (exact.length == 1) {
        rating = exact.first;
      }
    }
  }
  cache[key] = rating;
  return rating;
}

Future<double?> _rawRatingBeforeMatch(
  ResearchFacade facade,
  DbShooterRating rating,
  ShootingMatch match,
) async {
  final events = await facade.db.getRatingEventsByMatchIds(rating, matchIds: match.sourceIds);
  final ordered = [...events]..sort((a, b) => a.dateAndStageNumber.compareTo(b.dateAndStageNumber));
  if (ordered.isNotEmpty) {
    return ordered.first.oldRating;
  }
  return _rawRatingBefore(facade, rating, match.date, rating.rating);
}

List<DivisionHeatSummaryDto> summarizeDivisionHeat({
  required _ScorePool pool,
  required _HeatContext ctx,
  required int heatPercentile,
  required int heatMinCount,
}) {
  if (pool.kind == "overall") {
    final byDivision = <String, List<MatchEntry>>{};
    for (final shooter in pool.scores.keys) {
      if (shooter.reentry) {
        continue;
      }
      final label = shooter.division?.displayName ?? shooter.division?.name ?? "Unknown";
      byDivision.putIfAbsent(label, () => []).add(shooter);
    }
    final labels = byDivision.keys.toList()..sort();
    return [
      for (final label in labels)
        _heatSummary(
          pool: label,
          kind: "division",
          shooters: byDivision[label]!,
          places: _divisionPlaces(byDivision[label]!, pool.scores),
          ctx: ctx,
          heatPercentile: heatPercentile,
          heatMinCount: heatMinCount,
        ),
    ];
  }
  final shooters = pool.scores.keys.where((s) => !s.reentry).toList();
  if (shooters.isEmpty) {
    return [];
  }
  return [
    _heatSummary(
      pool: pool.label,
      kind: pool.kind,
      shooters: shooters,
      places: {for (final shooter in shooters) shooter: pool.scores[shooter]!.place},
      ctx: ctx,
      heatPercentile: heatPercentile,
      heatMinCount: heatMinCount,
    ),
  ];
}

/// Approximate in-division places when an overall pool is split by division:
/// rank by overall place. Hit-factor rescoring can reorder close finishers, so
/// prefer a division pool when exact division places matter.
Map<MatchEntry, int> _divisionPlaces(
  List<MatchEntry> shooters,
  Map<MatchEntry, RelativeMatchScore> scores,
) {
  final ranked = shooters.toList()
    ..sort((a, b) => scores[a]!.place.compareTo(scores[b]!.place));
  return {
    for (var i = 0; i < ranked.length; i++) ranked[i]: i + 1,
  };
}

DivisionHeatSummaryDto _heatSummary({
  required String pool,
  required String kind,
  required List<MatchEntry> shooters,
  required Map<MatchEntry, int> places,
  required _HeatContext ctx,
  required int heatPercentile,
  required int heatMinCount,
}) {
  var ratedCount = 0;
  var p90Count = 0;
  var p95Count = 0;
  var heatCount = 0;
  String? groupName;
  double? p90Rating;
  double? p95Rating;
  var mixedGroups = false;
  final names = <MatchEntry, _FinisherRating>{};
  for (final shooter in shooters) {
    final rating = ctx.ratings[shooter];
    if (rating == null) {
      continue;
    }
    ratedCount += 1;
    names[shooter] = rating;
    if (groupName == null) {
      groupName = rating.groupName;
      p90Rating = rating.p90Rating;
      p95Rating = rating.p95Rating;
    }
    else if (groupName != rating.groupName) {
      mixedGroups = true;
    }
    if (rating.ratingPct >= 90) {
      p90Count += 1;
    }
    if (rating.ratingPct >= 95) {
      p95Count += 1;
    }
    if (rating.ratingPct >= heatPercentile) {
      heatCount += 1;
    }
  }
  final p95Names = <String>[];
  final ranked = names.entries.where((e) => e.value.ratingPct >= 95).toList()
    ..sort((a, b) => b.value.ratingPct.compareTo(a.value.ratingPct));
  for (final entry in ranked) {
    p95Names.add("${entry.key.firstName} ${entry.key.lastName}".trim());
  }
  final heatRanked = names.entries.where((e) => e.value.ratingPct >= heatPercentile).toList()
    ..sort((a, b) => b.value.ratingPct.compareTo(a.value.ratingPct));
  final heatFinishers = [
    for (final entry in heatRanked)
      HeatFinisherDto(
        name: "${entry.key.firstName} ${entry.key.lastName}".trim(),
        place: places[entry.key] ?? 0,
        preMatchRating: entry.value.preMatchRating,
        ratingPct: entry.value.ratingPct,
      ),
  ];
  return DivisionHeatSummaryDto(
    pool: pool,
    kind: kind,
    groupName: mixedGroups ? null : groupName,
    competitorCount: shooters.length,
    ratedCount: ratedCount,
    p90Count: p90Count,
    p95Count: p95Count,
    p95Names: p95Names,
    heatCount: heatCount,
    heat: heatCount >= heatMinCount,
    heatPercentile: heatPercentile,
    heatMinCount: heatMinCount,
    heatFinishers: heatFinishers,
    p90Rating: mixedGroups ? null : p90Rating,
    p95Rating: mixedGroups ? null : p95Rating,
  );
}
