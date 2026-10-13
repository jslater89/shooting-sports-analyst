/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

/// Stage hit factor of shooters who were stably near a chosen LLR at match time.
///
/// The rating cohort comes from one group (default combined LO/CO). Hit factors
/// are then split by division and power factor, because major and minor scoring
/// are different point scales. A stage's reference hit factor is the median hit
/// factor of qualifying shooters on that stage. The baseline is the median of
/// those stage medians: above 1.0 is organically faster than a typical stage
/// for this cohort.
///
/// Pre-match state comes from the match rating event, not the shooter's rating
/// today. Rating is mean-reverted and variance is skill-drift aged to the match
/// date, matching the update. Someone who later leaves the band still counts
/// for matches where they were inside it.
///
/// Launch: dart run bin/db_oneoffs.dart SRH [startYear] [endYear] [project] [groupUuid] [ratingLow] [ratingHigh] [maxMomentum] [maxSd] [minPriorMatches] [minStageN] [csvPath]
/// Example: dart run bin/db_oneoffs.dart SRH 2024 2026

import "dart:io";
import "dart:math" as math;

import "package:collection/collection.dart";
import "package:dart_console/dart_console.dart";
import "package:isar_community/isar.dart";
import "package:shooting_sports_analyst/console/labeled_progress_bar.dart";
import "package:shooting_sports_analyst/console/repl.dart";
import "package:shooting_sports_analyst/data/database/analyst_database.dart";
import "package:shooting_sports_analyst/data/database/match/rating_project_database.dart";
import "package:shooting_sports_analyst/data/database/schema/ratings.dart";
import "package:shooting_sports_analyst/data/database/schema/ratings/db_rating_event.dart";
import "package:shooting_sports_analyst/data/ranking/raters/latentlog/latent_log_rater.dart";
import "package:shooting_sports_analyst/data/ranking/raters/latentlog/latent_log_rating.dart";
import "package:shooting_sports_analyst/data/ranking/raters/latentlog/latent_log_rating_event.dart";
import "package:shooting_sports_analyst/data/ranking/raters/latentlog/latent_log_settings.dart";
import "package:shooting_sports_analyst/data/sport/match/match.dart";
import "package:shooting_sports_analyst/data/sport/scoring/scoring.dart";
import "package:shooting_sports_analyst/data/sport/shooter/shooter.dart";

import "base.dart";

const String kDefaultLlrProjectName = "L2s Main LLR";
const String kDefaultGroupUuid = "uspsa-lo-co";
const int kDefaultStartYear = 2024;
const int kDefaultEndYear = 2026;
const double kDefaultRatingLow = 107;
const double kDefaultRatingHigh = 113;
const double kDefaultMaxAbsMomentum = 2;
const double kDefaultMaxDisplaySd = 6;
const int kDefaultMinPriorMatches = 0;
const int kDefaultMinStageN = 8;
const int kExtremeCount = 12;
const double kSuspectHitFactor = 30;

class StageReferenceHitFactorCommand extends DbOneoffCommand {
  StageReferenceHitFactorCommand(AnalystDatabase db) : super(db);

  @override
  final String key = "SRH";

  @override
  final String title = "Stage Reference Hit Factor";

  @override
  String? get description =>
      "Median stage hit factor of shooters stably near a chosen LLR. "
      "Defaults to 107–113 in LO/CO, 2024–2026, L2s Main LLR.";

  @override
  List<MenuArgument> get arguments => [
        IntMenuArgument(
          label: "Start year",
          required: false,
          defaultValue: kDefaultStartYear,
          description: "Inclusive start of the match-date year range.",
        ),
        IntMenuArgument(
          label: "End year",
          required: false,
          defaultValue: kDefaultEndYear,
          description: "Inclusive end of the match-date year range.",
        ),
        StringMenuArgument(
          label: "Project name",
          required: false,
          defaultValue: kDefaultLlrProjectName,
          description: "LLR rating project.",
        ),
        StringMenuArgument(
          label: "Group uuid",
          required: false,
          defaultValue: kDefaultGroupUuid,
          description: "Rating group that supplies the pre-match rating. "
              "Hit factors are still split by division and power factor.",
        ),
        StringMenuArgument(
          label: "Rating low",
          required: false,
          defaultValue: kDefaultRatingLow.toString(),
          description: "Inclusive lower display-rating bound at match time.",
        ),
        StringMenuArgument(
          label: "Rating high",
          required: false,
          defaultValue: kDefaultRatingHigh.toString(),
          description: "Inclusive upper display-rating bound at match time.",
        ),
        StringMenuArgument(
          label: "Max momentum",
          required: false,
          defaultValue: kDefaultMaxAbsMomentum.toString(),
          description: "Maximum absolute display momentum. 0 disables.",
        ),
        StringMenuArgument(
          label: "Max uncertainty",
          required: false,
          defaultValue: kDefaultMaxDisplaySd.toString(),
          description: "Maximum aged display standard deviation. 0 disables.",
        ),
        IntMenuArgument(
          label: "Min prior matches",
          required: false,
          defaultValue: kDefaultMinPriorMatches,
          description: "Minimum rated matches strictly before this match date. 0 disables. "
              "Aged uncertainty already drops class priors.",
        ),
        IntMenuArgument(
          label: "Min stage N",
          required: false,
          defaultValue: kDefaultMinStageN,
          description: "Minimum qualifying shooters on a stage to keep it.",
        ),
        StringMenuArgument(
          label: "CSV path",
          required: false,
          defaultValue: "",
          description: "Optional path for one row per kept stage. Empty skips the file.",
        ),
      ];

  @override
  Future<void> executor(Console console, List<MenuArgumentValue> arguments) async {
    final startYear = arguments
            .firstWhereOrNull((a) => a.argument.label == "Start year")
            ?.getAs<int>() ??
        kDefaultStartYear;
    final endYear = arguments
            .firstWhereOrNull((a) => a.argument.label == "End year")
            ?.getAs<int>() ??
        kDefaultEndYear;
    final projectName = arguments
            .firstWhereOrNull((a) => a.argument.label == "Project name")
            ?.getAs<String>()
            .trim() ??
        kDefaultLlrProjectName;
    final groupUuid = arguments
            .firstWhereOrNull((a) => a.argument.label == "Group uuid")
            ?.getAs<String>()
            .trim() ??
        kDefaultGroupUuid;
    final ratingLow = _parseDouble(
      arguments
          .firstWhereOrNull((a) => a.argument.label == "Rating low")
          ?.getAs<String>(),
      kDefaultRatingLow,
    );
    final ratingHigh = _parseDouble(
      arguments
          .firstWhereOrNull((a) => a.argument.label == "Rating high")
          ?.getAs<String>(),
      kDefaultRatingHigh,
    );
    final maxMomentum = _parseDouble(
      arguments
          .firstWhereOrNull((a) => a.argument.label == "Max momentum")
          ?.getAs<String>(),
      kDefaultMaxAbsMomentum,
    );
    final maxSd = _parseDouble(
      arguments
          .firstWhereOrNull((a) => a.argument.label == "Max uncertainty")
          ?.getAs<String>(),
      kDefaultMaxDisplaySd,
    );
    final minPriorMatches = arguments
            .firstWhereOrNull((a) => a.argument.label == "Min prior matches")
            ?.getAs<int>() ??
        kDefaultMinPriorMatches;
    final minStageN = arguments
            .firstWhereOrNull((a) => a.argument.label == "Min stage N")
            ?.getAs<int>() ??
        kDefaultMinStageN;
    final csvPath = arguments
            .firstWhereOrNull((a) => a.argument.label == "CSV path")
            ?.getAs<String>()
            .trim() ??
        "";

    if (startYear > endYear) {
      console.print("Start year ($startYear) must be <= end year ($endYear).");
      return;
    }
    if (ratingLow == null || ratingHigh == null || ratingLow > ratingHigh) {
      console.print("Rating low and rating high must be numbers, with low <= high.");
      return;
    }
    if (maxMomentum == null || maxMomentum < 0) {
      console.print("Max momentum must be a number >= 0 (0 disables).");
      return;
    }
    if (maxSd == null || maxSd < 0) {
      console.print("Max uncertainty must be a number >= 0 (0 disables).");
      return;
    }
    if (minPriorMatches < 0) {
      console.print("Min prior matches must be >= 0.");
      return;
    }
    if (minStageN < 3) {
      console.print("Min stage N must be at least 3 (got $minStageN).");
      return;
    }

    await _run(
      db,
      console,
      projectName: projectName.isEmpty ? kDefaultLlrProjectName : projectName,
      groupUuid: groupUuid.isEmpty ? kDefaultGroupUuid : groupUuid,
      startYear: startYear,
      endYear: endYear,
      ratingLow: ratingLow,
      ratingHigh: ratingHigh,
      maxAbsMomentum: maxMomentum,
      maxDisplaySd: maxSd,
      minPriorMatches: minPriorMatches,
      minStageN: minStageN,
      csvPath: csvPath,
    );
  }
}

double? _parseDouble(String? raw, double fallback) {
  if (raw == null) {
    return fallback;
  }
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return fallback;
  }
  return double.tryParse(trimmed);
}

Future<void> _run(
  AnalystDatabase db,
  Console console, {
  required String projectName,
  required String groupUuid,
  required int startYear,
  required int endYear,
  required double ratingLow,
  required double ratingHigh,
  required double maxAbsMomentum,
  required double maxDisplaySd,
  required int minPriorMatches,
  required int minStageN,
  required String csvPath,
}) async {
  final project = await db.getRatingProjectByName(projectName);
  if (project == null) {
    console.print("Rating project not found: $projectName");
    return;
  }
  if (!project.dbGroups.isLoaded) {
    await project.dbGroups.load();
  }

  final algorithm = project.settings.algorithm;
  if (algorithm is! LatentLogRater) {
    console.print(
      "Project $projectName uses ${algorithm.runtimeType}. "
      "Stage reference hit factor needs a latent-log project.",
    );
    return;
  }
  final settings = algorithm.settings;

  final group = project.groups.firstWhereOrNull((g) => g.uuid == groupUuid);
  if (group == null) {
    console.print("Rating group not found: $groupUuid");
    final nearby = project.groups
        .where((g) => g.uuid.toLowerCase().contains("lo") || g.uuid.toLowerCase().contains("co"))
        .map((g) => "${g.uuid} (${g.uiLabel})")
        .toList();
    if (nearby.isNotEmpty) {
      console.print("Groups whose uuid contains \"lo\" or \"co\":");
      for (final line in nearby) {
        console.print("  $line");
      }
    }
    return;
  }

  final sportName = group.sportName.toLowerCase();
  final pointers = project.matchPointers.where((p) {
    if (p.date == null) {
      return false;
    }
    if (p.sportName.toLowerCase() != sportName) {
      return false;
    }
    final year = p.date!.year;
    return year >= startYear && year <= endYear;
  }).toList()
    ..sort((a, b) => (a.date ?? DateTime(1970)).compareTo(b.date ?? DateTime(1970)));

  if (pointers.isEmpty) {
    console.print(
      "No $sportName match pointers in $projectName for $startYear–$endYear.",
    );
    return;
  }

  final band = <String, _Bucket>{};
  final stable = <String, _Bucket>{};
  final history = <int, _Prior>{};
  final stableRatings = <int>{};
  final bandRatings = <int>{};

  var hydrateErrors = 0;
  var rosterN = 0;
  var unmapped = 0;
  var noEvent = 0;
  var missingState = 0;
  var inBand = 0;
  var momentumFail = 0;
  var sdFail = 0;
  var historyFail = 0;
  var stableN = 0;
  var priorLike = 0;
  var suspectHf = 0;
  var nonHitFactorStages = 0;
  final bandRatingsDisplay = <double>[];
  final bandSds = <double>[];
  final bandMomentums = <double>[];

  final bar = LabeledProgressBar(
    maxValue: pointers.length,
    initialLabel: "Stage reference hit factor...",
    canHaveErrors: true,
  );

  for (final ptr in pointers) {
    bar.tick(ptr.name);

    final res = await ptr.getDbMatch(db, downloadIfMissing: false);
    if (res.isErr()) {
      hydrateErrors++;
      bar.error("Load failed: ${ptr.name}");
      continue;
    }
    final dbMatch = res.unwrap();
    if (dbMatch.shootersStoredSeparately) {
      await dbMatch.shooterLinks.load();
    }

    final hydrated = await dbMatch.hydrate();
    if (hydrated.isErr()) {
      hydrateErrors++;
      bar.error("Hydrate failed: ${ptr.name}");
      continue;
    }
    final match = hydrated.unwrap();
    final matchId = match.sourceIds.firstOrNull ?? ptr.sourceIds.firstOrNull ?? match.name;
    final noted = <int>{};
    final bandMatchRatios = <String, List<double>>{};
    final stableMatchRatios = <String, List<double>>{};

    final scores = match.getScoresFromFilters(group.filters);
    for (final kv in scores.entries) {
      final entry = kv.key;
      final rel = kv.value;
      if (entry.dq) {
        continue;
      }
      if (!group.filters.reentries && entry.reentry) {
        continue;
      }
      rosterN++;

      final dbRating = _lookupRating(db, project, group, entry);
      if (dbRating == null) {
        unmapped++;
        continue;
      }
      if (!noted.add(dbRating.id)) {
        continue;
      }

      final events = dbRating.matchEventsSync(match);
      if (events.isEmpty) {
        noEvent++;
        continue;
      }
      final event = _preMatchEvent(events);
      if (event == null || event.doubleData.length < 3) {
        missingState++;
        continue;
      }

      final prior = _ensurePrior(
        db,
        history,
        dbRating,
        match.date,
        matchId,
        countMatches: minPriorMatches > 0,
      );
      final daysSince = prior.lastEventDate == null
          ? 0
          : math.max(0, match.date.difference(prior.lastEventDate!).inDays);
      final matchesBefore = prior.matchesBefore;
      prior.matchesBefore += 1;
      prior.lastEventDate = match.date;

      final wrapped = LatentLogRatingEvent.wrap(event, settings: settings);
      final agedInternal = _agedRating(
        rating: wrapped.oldRating,
        daysSinceCommit: daysSince,
        settings: settings,
      );
      final displayRating = agedInternal * settings.scaleFactor + settings.scaleOffset;
      if (displayRating < ratingLow || displayRating > ratingHigh) {
        continue;
      }

      final agedVariance = _agedVariance(
        variance: math.max(0, wrapped.oldVariance),
        daysSinceCommit: daysSince,
        settings: settings,
      );
      final displaySd = math.sqrt(agedVariance) * settings.scaleFactor;
      final absMomentum = (wrapped.oldMomentum * settings.scaleFactor).abs();

      inBand++;
      if (displaySd >= 15) {
        priorLike++;
      }
      bandRatings.add(dbRating.id);
      bandRatingsDisplay.add(displayRating);
      bandSds.add(displaySd);
      bandMomentums.add(absMomentum);

      final momentumOk = maxAbsMomentum <= 0 || absMomentum <= maxAbsMomentum;
      final sdOk = maxDisplaySd <= 0 || displaySd <= maxDisplaySd;
      final historyOk = matchesBefore >= minPriorMatches;
      if (!momentumOk) {
        momentumFail++;
      }
      if (!sdOk) {
        sdFail++;
      }
      if (!historyOk) {
        historyFail++;
      }

      final label = _bucketLabel(entry);
      if (rel.ratio > 0) {
        bandMatchRatios.putIfAbsent(label, () => []).add(rel.ratio);
      }
      _addStageHitFactors(
        buckets: band,
        label: label,
        matchId: matchId,
        match: match,
        rel: rel,
        onSuspect: () => suspectHf++,
        onNonHitFactor: () => nonHitFactorStages++,
      );

      if (!momentumOk || !sdOk || !historyOk) {
        continue;
      }

      stableN++;
      stableRatings.add(dbRating.id);
      if (rel.ratio > 0) {
        stableMatchRatios.putIfAbsent(label, () => []).add(rel.ratio);
      }
      _addStageHitFactors(
        buckets: stable,
        label: label,
        matchId: matchId,
        match: match,
        rel: rel,
        onSuspect: () {},
        onNonHitFactor: () {},
      );
    }

    _foldMatchSpreads(band, bandMatchRatios);
    _foldMatchSpreads(stable, stableMatchRatios);
  }

  bar.complete();

  final buf = StringBuffer()
    ..writeln("Stage reference hit factor")
    ..writeln("Project: $projectName")
    ..writeln("Group: ${group.uiLabel} ($groupUuid)")
    ..writeln(
      "Scale: display = internal * ${settings.scaleFactor.toStringAsFixed(0)} + ${settings.scaleOffset.toStringAsFixed(0)}",
    )
    ..writeln("Years: $startYear–$endYear")
    ..writeln("Pointers: ${pointers.length}  hydrate errors: $hydrateErrors")
    ..writeln("Identity: maybeKnownShooterSync(usePossibleMemberNumbers: true)")
    ..writeln(
      "Pre-match rating: aged oldRating of the lowest-stageNumber event for the match",
    )
    ..writeln(
      "Uncertainty: oldVariance plus skill-drift aging since the previous event",
    )
    ..writeln("Momentum: committed oldMomentum, in display points")
    ..writeln(
      "Band: ${ratingLow.toStringAsFixed(1)}–${ratingHigh.toStringAsFixed(1)} display",
    )
    ..writeln(
      "Stability: |momentum| <= ${_gate(maxAbsMomentum)}, "
      "aged SD <= ${_gate(maxDisplaySd)}, "
      "prior matches ${minPriorMatches <= 0 ? "off" : ">= $minPriorMatches"}",
    )
    ..writeln("Min shooters per kept stage: $minStageN")
    ..writeln(
      "Hit factors are split by division and power factor so major and minor "
      "point scales stay separate.",
    )
    ..writeln("Roster rows: $rosterN  unmapped: $unmapped  no rating event: $noEvent  missing LLR state: $missingState")
    ..writeln(
      "In band: $inBand shooter-matches (${bandRatings.length} ratings)  "
      "stable: $stableN shooter-matches (${stableRatings.length} ratings)",
    )
    ..writeln(
      "In-band gate failures (a row can fail more than one): "
      "momentum $momentumFail, uncertainty $sdFail, prior matches $historyFail",
    );

  if (bandSds.isNotEmpty) {
    final sdSorted = [...bandSds]..sort();
    final momSorted = [...bandMomentums]..sort();
    final ratingSorted = [...bandRatingsDisplay]..sort();
    buf
      ..writeln(
        "In-band display rating  p10 ${_n(_pct(ratingSorted, 0.10))}  "
        "p50 ${_n(_pct(ratingSorted, 0.50))}  p90 ${_n(_pct(ratingSorted, 0.90))}",
      )
      ..writeln(
        "In-band aged SD         p10 ${_n(_pct(sdSorted, 0.10))}  "
        "p50 ${_n(_pct(sdSorted, 0.50))}  p90 ${_n(_pct(sdSorted, 0.90))}",
      )
      ..writeln(
        "In-band |momentum|      p10 ${_n(_pct(momSorted, 0.10))}  "
        "p50 ${_n(_pct(momSorted, 0.50))}  p90 ${_n(_pct(momSorted, 0.90))}",
      )
      ..writeln(
        "In-band near a class prior (aged SD >= 15): $priorLike. "
        "Unclassified starts at display 108, so the raw band piles up there.",
      );
  }

  buf
    ..writeln("Suspect hit factors above $kSuspectHitFactor dropped: $suspectHf")
    ..writeln("Non-hit-factor stage rows skipped: $nonHitFactorStages")
    ..writeln("");

  final labels = {...band.keys, ...stable.keys}.toList()..sort(_labelSort);
  if (labels.isEmpty) {
    buf.writeln("No shooter-matches fell in the rating band.");
    console.print(buf.toString());
    return;
  }

  buf.writeln("Band only, before stability filters");
  for (final label in labels) {
    final bucket = band[label];
    if (bucket == null) {
      continue;
    }
    _writeBucketSummary(buf, bucket, minStageN: minStageN, verbose: false);
  }
  buf.writeln("");
  buf.writeln("Stable cohort");
  for (final label in labels) {
    final bucket = stable[label];
    if (bucket == null) {
      buf.writeln("$label: no stable shooter-matches");
      buf.writeln("");
      continue;
    }
    _writeBucketSummary(buf, bucket, minStageN: minStageN, verbose: true);
  }

  if (csvPath.isNotEmpty) {
    final csv = StringBuffer()
      ..writeln(
        "divisionPowerFactor,date,match,stage,stageId,classifier,classifierNumber,"
        "n,medianHf,meanHf,p25Hf,p75Hf,iqrOverMedian,baselineHf,ratioToBaseline",
      );
    for (final label in labels) {
      final bucket = stable[label];
      if (bucket == null) {
        continue;
      }
      final kept = _keptStages(bucket, minStageN);
      final baseline = _medianOf(kept.map((s) => _medianOf(s.hitFactors)).toList());
      for (final stage in kept) {
        final sorted = [...stage.hitFactors]..sort();
        final median = _pct(sorted, 0.50);
        final p25 = _pct(sorted, 0.25);
        final p75 = _pct(sorted, 0.75);
        final iqrRatio = median > 0 ? (p75 - p25) / median : double.nan;
        final ratio = baseline > 0 ? median / baseline : double.nan;
        csv.writeln([
          _csv(label),
          stage.date.toIso8601String().split("T").first,
          _csv(stage.matchName),
          _csv(stage.stageName),
          stage.stageId.toString(),
          stage.classifier ? "true" : "false",
          _csv(stage.classifierNumber),
          sorted.length.toString(),
          median.toStringAsFixed(4),
          _mean(sorted).toStringAsFixed(4),
          p25.toStringAsFixed(4),
          p75.toStringAsFixed(4),
          iqrRatio.toStringAsFixed(4),
          baseline.toStringAsFixed(4),
          ratio.toStringAsFixed(4),
        ].join(","));
      }
    }
    try {
      File(csvPath).writeAsStringSync(csv.toString());
      buf.writeln("Wrote kept stable stages to $csvPath");
    }
    catch (e) {
      buf.writeln("CSV write failed for $csvPath: $e");
    }
  }

  console.print(buf.toString());
}

bool _addStageHitFactors({
  required Map<String, _Bucket> buckets,
  required String label,
  required String matchId,
  required ShootingMatch match,
  required RelativeMatchScore rel,
  required void Function() onSuspect,
  required void Function() onNonHitFactor,
}) {
  var added = false;
  for (final stageKv in rel.stageScores.entries) {
    final stage = stageKv.key;
    final stageScore = stageKv.value;
    if (stage.scoring is! HitFactorScoring) {
      onNonHitFactor();
      continue;
    }
    if (stageScore.score.dnf) {
      continue;
    }
    final hf = stageScore.score.hitFactor;
    if (!hf.isFinite || hf <= 0) {
      continue;
    }
    if (hf > kSuspectHitFactor) {
      onSuspect();
      continue;
    }
    final bucket = buckets.putIfAbsent(label, () => _Bucket(label));
    final key = "$matchId|${stage.stageId}";
    final sample = bucket.stages.putIfAbsent(
      key,
      () => _StageSample(
        date: match.date,
        matchName: match.name,
        stageName: stage.name,
        stageId: stage.stageId,
        classifier: stage.classifier,
        classifierNumber: stage.classifierNumber,
      ),
    );
    sample.hitFactors.add(hf);
    added = true;
  }
  return added;
}

void _foldMatchSpreads(Map<String, _Bucket> buckets, Map<String, List<double>> ratios) {
  for (final kv in ratios.entries) {
    if (kv.value.length < 3) {
      continue;
    }
    final sorted = [...kv.value]..sort();
    final iqr = _pct(sorted, 0.75) - _pct(sorted, 0.25);
    buckets[kv.key]?.matchPercentIqrs.add(iqr * 100);
  }
}

void _writeBucketSummary(
  StringBuffer buf,
  _Bucket bucket, {
  required int minStageN,
  required bool verbose,
}) {
  final kept = _keptStages(bucket, minStageN);
  final thin = bucket.stages.length - kept.length;
  final medians = kept.map((s) => _medianOf(s.hitFactors)).toList()..sort();
  buf.writeln(bucket.label);
  buf.writeln(
    "  Stages with any reference shooter: ${bucket.stages.length}  "
    "kept (n >= $minStageN): ${kept.length}  thin: $thin",
  );
  if (medians.isEmpty) {
    buf.writeln("  No stage reached n >= $minStageN.");
    buf.writeln("");
    return;
  }

  final baseline = _pct(medians, 0.50);
  final iqrRatios = <double>[];
  for (final stage in kept) {
    final sorted = [...stage.hitFactors]..sort();
    final median = _pct(sorted, 0.50);
    if (median <= 0) {
      continue;
    }
    final iqr = _pct(sorted, 0.75) - _pct(sorted, 0.25);
    iqrRatios.add(iqr / median);
  }
  iqrRatios.sort();

  buf.writeln(
    "  Stage-median HF  n=${medians.length}  "
    "p10 ${_n(_pct(medians, 0.10))}  p25 ${_n(_pct(medians, 0.25))}  "
    "p50 ${_n(baseline)}  p75 ${_n(_pct(medians, 0.75))}  p90 ${_n(_pct(medians, 0.90))}",
  );
  buf.writeln("  Baseline (median of stage medians): ${_n(baseline)}");
  if (iqrRatios.isNotEmpty) {
    buf.writeln(
      "  Within-stage IQR/median  p50 ${_pct(iqrRatios, 0.50).toStringAsFixed(2)}  "
      "p90 ${_pct(iqrRatios, 0.90).toStringAsFixed(2)}",
    );
  }
  if (bucket.matchPercentIqrs.isNotEmpty) {
    final spreads = [...bucket.matchPercentIqrs]..sort();
    buf.writeln(
      "  Within-match finish spread, matches with >= 3 reference shooters: "
      "${spreads.length}  median IQR ${_n(_pct(spreads, 0.50))} percentage points",
    );
  }
  buf.writeln("  ${_hfBins(medians)}");

  if (!verbose) {
    buf.writeln("");
    return;
  }

  final ratios = medians.map((m) => baseline > 0 ? m / baseline : double.nan).toList()..sort();
  buf.writeln("  ${_ratioBins(ratios)}");
  buf.writeln(_histogram(medians));

  final byMedian = [...kept]..sort((a, b) => _medianOf(a.hitFactors).compareTo(_medianOf(b.hitFactors)));
  buf.writeln("  Slowest");
  for (final stage in byMedian.take(kExtremeCount)) {
    buf.writeln("    ${_stageLine(stage, baseline)}");
  }
  buf.writeln("  Fastest");
  for (final stage in byMedian.reversed.take(kExtremeCount)) {
    buf.writeln("    ${_stageLine(stage, baseline)}");
  }
  buf.writeln("");
}

List<_StageSample> _keptStages(_Bucket bucket, int minStageN) {
  return bucket.stages.values.where((s) => s.hitFactors.length >= minStageN).toList();
}

String _stageLine(_StageSample stage, double baseline) {
  final sorted = [...stage.hitFactors]..sort();
  final median = _pct(sorted, 0.50);
  final iqr = _pct(sorted, 0.75) - _pct(sorted, 0.25);
  final ratio = baseline > 0 ? median / baseline : double.nan;
  final date = stage.date.toIso8601String().split("T").first;
  final classifier = stage.classifier && stage.classifierNumber.isNotEmpty
      ? " [${stage.classifierNumber}]"
      : "";
  return "$date  ${_clip(stage.matchName, 42)}  "
      "${_clip(stage.stageName, 28)}$classifier  "
      "n=${sorted.length}  med=${_n(median)}  iqr=${_n(iqr)}  "
      "vs base=${ratio.toStringAsFixed(2)}";
}

String _hfBins(List<double> sortedMedians) {
  final edges = [4.0, 6.0, 8.0, 10.0];
  final counts = List<int>.filled(edges.length + 1, 0);
  for (final value in sortedMedians) {
    var placed = false;
    for (var i = 0; i < edges.length; i++) {
      if (value < edges[i]) {
        counts[i]++;
        placed = true;
        break;
      }
    }
    if (!placed) {
      counts[edges.length]++;
    }
  }
  final total = sortedMedians.length;
  String part(int count) => "$count (${_share(count, total)})";
  return "HF bins  <4 ${part(counts[0])}  "
      "4–6 ${part(counts[1])}  "
      "6–8 ${part(counts[2])}  "
      "8–10 ${part(counts[3])}  "
      ">=10 ${part(counts[4])}";
}

String _ratioBins(List<double> sortedRatios) {
  final edges = [0.75, 0.90, 1.10, 1.30];
  final counts = List<int>.filled(edges.length + 1, 0);
  for (final value in sortedRatios) {
    if (!value.isFinite) {
      continue;
    }
    var placed = false;
    for (var i = 0; i < edges.length; i++) {
      if (value < edges[i]) {
        counts[i]++;
        placed = true;
        break;
      }
    }
    if (!placed) {
      counts[edges.length]++;
    }
  }
  final total = sortedRatios.where((v) => v.isFinite).length;
  String part(int count) => "$count (${_share(count, total)})";
  return "Ratio to baseline  <0.75 ${part(counts[0])}  "
      "0.75–0.90 ${part(counts[1])}  "
      "0.90–1.10 ${part(counts[2])}  "
      "1.10–1.30 ${part(counts[3])}  "
      ">=1.30 ${part(counts[4])}";
}

String _histogram(List<double> sortedMedians) {
  if (sortedMedians.isEmpty) {
    return "";
  }
  final low = sortedMedians.first.floor();
  final high = math.max(low, sortedMedians.last.ceil());
  final counts = <int, int>{};
  var maxCount = 0;
  for (final value in sortedMedians) {
    final bin = value.floor().clamp(low, high);
    final next = (counts[bin] ?? 0) + 1;
    counts[bin] = next;
    if (next > maxCount) {
      maxCount = next;
    }
  }
  final lines = StringBuffer("  Stage-median histogram\n");
  for (var bin = low; bin <= high; bin++) {
    final count = counts[bin] ?? 0;
    final width = maxCount == 0 ? 0 : ((count / maxCount) * 32).round();
    final bar = width <= 0 ? "" : "#" * width;
    lines.writeln(
      "    ${bin.toString().padLeft(2)}–${(bin + 1).toString().padLeft(2)}  "
      "${bar.padRight(32)}  $count",
    );
  }
  return lines.toString().trimRight();
}

String _bucketLabel(MatchEntry entry) {
  final division = entry.division?.shortDisplayName ?? "Unknown";
  final powerFactor = entry.powerFactor.name;
  return "$division $powerFactor";
}

int _labelSort(String a, String b) {
  int rank(String label) {
    if (label.startsWith("LO ")) {
      return 0;
    }
    if (label.startsWith("CO ")) {
      return 1;
    }
    return 2;
  }

  final byRank = rank(a).compareTo(rank(b));
  if (byRank != 0) {
    return byRank;
  }
  return a.compareTo(b);
}

_Prior _ensurePrior(
  AnalystDatabase db,
  Map<int, _Prior> history,
  DbShooterRating rating,
  DateTime matchDate,
  String matchId, {
  required bool countMatches,
}) {
  final cached = history[rating.id];
  if (cached != null) {
    return cached;
  }

  final matchesBefore = countMatches
      ? rating.events.filter().dateLessThan(matchDate).matchIdProperty().findAllSync().toSet().length
      : 0;
  final priors = db.getRatingEventsForSync(
    rating,
    before: matchDate.subtract(const Duration(milliseconds: 1)),
    limit: 1,
  );
  final created = _Prior(
    matchesBefore: matchesBefore,
    lastEventDate: priors.firstOrNull?.matchId == matchId ? null : priors.firstOrNull?.date,
  );
  history[rating.id] = created;
  return created;
}

double _agedRating({
  required double rating,
  required int daysSinceCommit,
  required LatentLogSettings settings,
}) {
  final years = daysSinceCommit / 365.0;
  final effectiveYears = math.max(0.0, years - settings.meanReversionGraceYears);
  final deviation = rating - settings.startingRating;
  return settings.startingRating +
      deviation * math.exp(-settings.meanReversionDecayRate * effectiveYears);
}

double _agedVariance({
  required double variance,
  required int daysSinceCommit,
  required LatentLogSettings settings,
}) {
  final periods = math.max(0, daysSinceCommit) / LatentLogRating.ratingPeriodLengthInDays;
  return math.min(settings.maximumVariance, variance + settings.skillDriftRate * periods);
}

DbRatingEvent? _preMatchEvent(List<DbRatingEvent> events) {
  if (events.isEmpty) {
    return null;
  }
  final sorted = [...events]..sort((a, b) => a.stageNumber.compareTo(b.stageNumber));
  return sorted.first;
}

DbShooterRating? _lookupRating(
  AnalystDatabase db,
  DbRatingProject project,
  RatingGroup group,
  MatchEntry entry,
) {
  for (final mn in _memberNumberCandidates(entry)) {
    final dbRating = db.maybeKnownShooterSync(
      project: project,
      group: group,
      memberNumber: mn,
      usePossibleMemberNumbers: true,
    );
    if (dbRating != null) {
      return dbRating;
    }
  }
  return null;
}

Iterable<String> _memberNumberCandidates(MatchEntry entry) sync* {
  final seen = <String>{};
  for (final candidate in [
    entry.memberNumber,
    entry.originalMemberNumber,
    ...entry.knownMemberNumbers,
  ]) {
    final trimmed = candidate.trim();
    if (trimmed.isEmpty || trimmed == "(invalid)") {
      continue;
    }
    if (seen.add(trimmed)) {
      yield trimmed;
    }
  }
}

double _pct(List<double> sorted, double p) {
  if (sorted.isEmpty) {
    return double.nan;
  }
  if (sorted.length == 1) {
    return sorted.first;
  }
  final rank = p * (sorted.length - 1);
  final lo = rank.floor();
  final hi = rank.ceil();
  if (lo == hi) {
    return sorted[lo];
  }
  final t = rank - lo;
  return sorted[lo] * (1 - t) + sorted[hi] * t;
}

double _medianOf(List<double> values) {
  final sorted = [...values]..sort();
  return _pct(sorted, 0.50);
}

double _mean(List<double> values) {
  var sum = 0.0;
  for (final value in values) {
    sum += value;
  }
  return sum / values.length;
}

String _n(double value) => value.toStringAsFixed(2);

String _gate(double value) => value <= 0 ? "off" : value.toStringAsFixed(1);

String _share(int count, int total) {
  if (total <= 0) {
    return "0%";
  }
  return "${(100 * count / total).toStringAsFixed(0)}%";
}

String _clip(String value, int max) {
  if (value.length <= max) {
    return value.padRight(max);
  }
  return "${value.substring(0, max - 1)}…";
}

String _csv(String value) {
  if (value.contains(",") || value.contains("\"") || value.contains("\n")) {
    return "\"${value.replaceAll("\"", "\"\"")}\"";
  }
  return value;
}

class _Bucket {
  _Bucket(this.label);

  final String label;
  final Map<String, _StageSample> stages = {};
  final List<double> matchPercentIqrs = [];
}

class _StageSample {
  _StageSample({
    required this.date,
    required this.matchName,
    required this.stageName,
    required this.stageId,
    required this.classifier,
    required this.classifierNumber,
  });

  final DateTime date;
  final String matchName;
  final String stageName;
  final int stageId;
  final bool classifier;
  final String classifierNumber;
  final List<double> hitFactors = [];
}

class _Prior {
  _Prior({
    required this.matchesBefore,
    required this.lastEventDate,
  });

  int matchesBefore;
  DateTime? lastEventDate;
}
