// ignore_for_file: avoid_print

/*
 * Empirical diagnostics for latent log-ratio / hit-factor structure.
 *
 * Run from repo root:
 *   dart run research/latent-log-ratio/scripts/latent_log_empirical.dart
 *
 * Requires the usual SSA `config.toml`, `db/` with data, and `libisar.so` (or
 * `libisar.dylib` / `isar.dll`) in the package root so Isar can load when the
 * entrypoint lives under [research/] (see [_initializeIsarCoreFromPackageRoot]).
 */

import "dart:ffi";
import "dart:io";
import "dart:math";

import "package:collection/collection.dart";
import "package:isar_community/src/native/isar_core.dart" show initializeCoreBinary;
import "package:normal/normal.dart";
import "package:shooting_sports_analyst/config/serialized_config.dart";
import "package:shooting_sports_analyst/data/database/analyst_database.dart";
import "package:shooting_sports_analyst/data/database/match/hydrated_cache.dart";
import "package:shooting_sports_analyst/data/database/match/rating_project_database.dart";
import "package:shooting_sports_analyst/data/ranking/deduplication/shooter_deduplicator.dart";
import "package:shooting_sports_analyst/data/sport/builtins/ipsc.dart";
import "package:shooting_sports_analyst/data/sport/builtins/uspsa.dart";
import "package:shooting_sports_analyst/data/sport/scoring/scoring.dart";
import "package:shooting_sports_analyst/data/sport/shooter/shooter.dart";
import "package:shooting_sports_analyst/flutter_native_providers.dart";
import "package:shooting_sports_analyst/logger.dart";
import "package:shooting_sports_analyst/server/providers.dart";

/// Matches [LatentLogRater._scoreFloor] — log evidence uses `log(ratio.clamp(floor, 1.0))`.
const double _kScoreFloor = 0.01;

const String _kProjectName = "L2s Main LLR";

final _log = SSALogger("LatentLogEmpirical");

/// Isar loads native libs relative to the entrypoint; scripts under [research/] must run with CWD at the package root.
void _ensurePackageRootAsWorkingDirectory() {
  var root = File.fromUri(Platform.script).parent;
  while(true) {
    if(File("${root.path}/pubspec.yaml").existsSync()) {
      Directory.current = root;
      return;
    }
    var parent = root.parent;
    if(parent.path == root.path) {
      return;
    }
    root = parent;
  }
}

/// [Isar] resolves the native binary next to [Platform.script]; scripts under [research/] must preload the lib from the package root (same layout as a Flutter app build).
void _initializeIsarCoreFromPackageRoot() {
  final names = ["libisar.so", "libisar.dylib", "isar.dll"];
  for(final n in names) {
    final f = File("${Directory.current.path}/$n");
    if(f.existsSync()) {
      initializeCoreBinary(libraries: {Abi.current(): f.path});
      return;
    }
  }
}

Future<void> main(List<String> args) async {
  _ensurePackageRootAsWorkingDirectory();
  _initializeIsarCoreFromPackageRoot();

  FlutterOrNative.debugModeProvider = ServerDebugProvider();
  FlutterOrNative.isolateModeProvider = ServerDebugProvider(isMultiIsolate: false);
  SSALogger.consoleOutput = true;
  SSALogger.fileOutput = false;
  await _log.ready;

  await ConfigLoader().readyFuture;

  var db = AnalystDatabase();
  await db.ready;

  var project = await db.getRatingProjectByName(_kProjectName);
  if(project == null) {
    print("Rating project not found: $_kProjectName");
    exitCode = 1;
    return;
  }

  var groupsRes = await project.getGroups();
  if(groupsRes.isErr()) {
    print("Error loading groups: ${groupsRes.unwrapErr()}");
    exitCode = 1;
    return;
  }
  var groupsList = groupsRes.unwrap();
  if(groupsList.isEmpty) {
    print("No rating groups on project $_kProjectName");
    exitCode = 1;
    return;
  }

  var sport = project.sport;
  var numberProcessor = ShooterDeduplicator.numberProcessor(sport);

  /// Per [DbShooterRating.id], all raw hit factors observed (Hit Factor stages only).
  final hfByRatingId = <int, List<double>>{};

  /// All valid ln(HF) for Q–Q (same observations as pooled HF analysis).
  final lnHfSample = <double>[];

  /// Per-stage-instance skewness of ln(ratio) evidence (aligned with rater floor).
  final perStageLnRatioSkews = <double>[];

  /// Per [DbShooterRating.id], match [RelativeMatchScore.points] (complete matches only).
  final matchPointsByRatingId = <int, List<double>>{};

  /// ln(match points) for Q–Q on the match aggregate scale.
  final lnMatchPointsSample = <double>[];

  /// Per (match, group) skewness of ln(match ratio to winner), complete scores only.
  final perMatchLnRatioSkews = <double>[];

  int matchesProcessed = 0;
  int matchesSkipped = 0;
  int missingRatingLookups = 0;
  int hfRows = 0;
  int matchScoreRows = 0;

  var matchPointers = project.matchPointers;
  print("Matches in project: ${matchPointers.length}");

  for(var i = 0; i < matchPointers.length; i++) {
    var matchPointer = matchPointers[i];
    var dbMatch = await db.getMatchByAnySourceId(matchPointer.sourceIds);
    if(dbMatch == null) {
      matchesSkipped++;
      continue;
    }
    var hydratedRes = await HydratedMatchCache().get(dbMatch);
    if(hydratedRes.isErr()) {
      _log.w("Hydrate failed: ${hydratedRes.unwrapErr()}");
      matchesSkipped++;
      continue;
    }
    var hydratedMatch = hydratedRes.unwrap();
    matchesProcessed++;

    if((i + 1) % 200 == 0) {
      print("… processed ${i + 1} / ${matchPointers.length} match pointers");
    }

    for(var group in groupsList) {
      var filters = group.filters;
      if(sport.name == uspsaSport.name && hydratedMatch.sport.name == ipscSport.name) {
        filters = group.ipscCompatibleFilters();
      }
      Map<MatchEntry, RelativeMatchScore> scores;
      try {
        scores = hydratedMatch.getScoresFromFilters(filters);
      }
      catch(e, st) {
        _log.w("getScoresFromFilters failed: $e", error: e, stackTrace: st);
        continue;
      }

      var hfStages = hydratedMatch.stages.where((s) => s.scoring is HitFactorScoring).toList();
      for(var stage in hfStages) {
        var lnValues = <double>[];
        for(var e in scores.entries) {
          var rel = e.value;
          var st = rel.stageScores[stage];
          if(st == null) {
            continue;
          }
          if(st.isDnf) {
            continue;
          }
          var r = st.ratio;
          if(r <= 0) {
            continue;
          }
          lnValues.add(log(max(_kScoreFloor, min(1.0, r))));
        }
        if(lnValues.length >= 3) {
          var skew = fisherPearsonSkewness(lnValues);
          if(!skew.isNaN) {
            perStageLnRatioSkews.add(skew);
          }
        }
      }

      {
        var lnMatchRatios = <double>[];
        for(var e in scores.entries) {
          var rel = e.value;
          if(!rel.isComplete) {
            continue;
          }
          var r = rel.ratio;
          if(r <= 0) {
            continue;
          }
          lnMatchRatios.add(log(max(_kScoreFloor, min(1.0, r))));
        }
        if(lnMatchRatios.length >= 3) {
          var skew = fisherPearsonSkewness(lnMatchRatios);
          if(!skew.isNaN) {
            perMatchLnRatioSkews.add(skew);
          }
        }
      }

      for(var entry in scores.entries) {
        var shooter = entry.key;
        var rel = entry.value;
        var processed = numberProcessor(shooter.memberNumber);
        var dbRating = db.maybeKnownShooterSync(
          project: project,
          group: group,
          memberNumber: processed,
          usePossibleMemberNumbers: true,
          useCache: true,
        );
        if(dbRating == null) {
          missingRatingLookups++;
          continue;
        }
        var ratingKey = dbRating.id;

        if(rel.isComplete) {
          var mp = rel.points;
          if(mp > 0 && !mp.isNaN && !mp.isInfinite) {
            matchScoreRows++;
            matchPointsByRatingId.putIfAbsent(ratingKey, () => []).add(mp);
            lnMatchPointsSample.add(log(mp));
          }
        }

        for(var stageEntry in rel.stageScores.entries) {
          var stage = stageEntry.key;
          if(stage.scoring is! HitFactorScoring) {
            continue;
          }
          var stageScore = stageEntry.value;
          if(stageScore.isDnf) {
            continue;
          }
          var hf = stageScore.score.hitFactor;
          if(hf <= 0 || hf.isInfinite || hf.isNaN) {
            continue;
          }

          hfRows++;
          hfByRatingId.putIfAbsent(ratingKey, () => []).add(hf);
          lnHfSample.add(log(hf));
        }
      }
    }
  }

  print("");
  print("=== Summary ===");
  print("Match pointers processed (hydrated ok): $matchesProcessed");
  print("Match pointers skipped: $matchesSkipped");
  print("Missing DbShooterRating lookups (row skipped): $missingRatingLookups");
  print("");
  print("--- Stage-level (Hit Factor stages only) ---");
  print("HF stage observations (rows): $hfRows");
  print("");
  _printHomoscedasticityDeciles(
    hfByRatingId,
    sectionTitle: "Test 1 (stage): Deciles by mean HF (key = DbShooterRating.id)",
    nColumnLabel: "n (stage HFs)",
  );
  print("");
  await _writeQqCsv(
    lnHfSample,
    csvPath: "research/latent-log-ratio/qq_ln_hf_sample.csv",
    sampleColumnHeader: "sample_ln_hf",
    sectionTitle: "Test 2 (stage): Q–Q for ln(HF)",
  );
  print("");
  _printSkewnessSummary(
    perStageLnRatioSkews,
    sectionTitle: "Test 3 (stage): ln(ratio) skewness (per HF stage instance, floor $_kScoreFloor)",
  );

  print("");
  print("--- Match-level (full match score, complete matches only) ---");
  print("Match score observations (rows): $matchScoreRows");
  print("");
  _printHomoscedasticityDeciles(
    matchPointsByRatingId,
    sectionTitle: "Test 1 (match): Deciles by mean match points (key = DbShooterRating.id)",
    nColumnLabel: "n (match pts)",
    valueLabel: "match pts",
  );
  print("");
  await _writeQqCsv(
    lnMatchPointsSample,
    csvPath: "research/latent-log-ratio/qq_ln_match_points_sample.csv",
    sampleColumnHeader: "sample_ln_match_points",
    sectionTitle: "Test 2 (match): Q–Q for ln(match points)",
  );
  print("");
  _printSkewnessSummary(
    perMatchLnRatioSkews,
    sectionTitle: "Test 3 (match): ln(match ratio) skewness (per match × group, complete scores, floor $_kScoreFloor)",
  );

  print("");
  print("Done.");
}

void _printHomoscedasticityDeciles(
  Map<int, List<double>> valuesByRatingId, {
  required String sectionTitle,
  required String nColumnLabel,
  String valueLabel = "HF",
}) {
  print("=== $sectionTitle ===");

  var shooters = valuesByRatingId.entries
      .map((e) => MapEntry(e.key, e.value.fold(0.0, (a, b) => a + b) / e.value.length))
      .toList();
  shooters.sort((a, b) {
    var c = a.value.compareTo(b.value);
    if(c != 0) {
      return c;
    }
    return a.key.compareTo(b.key);
  });

  if(shooters.length < 10) {
    print("Not enough distinct shooters with data (${shooters.length}) for 10 deciles.");
    return;
  }

  final decileRaw = List.generate(10, (_) => <double>[]);
  final decileLn = List.generate(10, (_) => <double>[]);

  for(var i = 0; i < shooters.length; i++) {
    var d = min(9, (i * 10) ~/ shooters.length);
    var id = shooters[i].key;
    for(var v in valuesByRatingId[id]!) {
      decileRaw[d].add(v);
      decileLn[d].add(log(v));
    }
  }

  final meanRawPerDecile = <double>[];
  final varRawPerDecile = <double>[];
  final meanLnPerDecile = <double>[];
  final varLnPerDecile = <double>[];
  final ns = <int>[];

  for(var d = 0; d < 10; d++) {
    var xs = decileRaw[d];
    ns.add(xs.length);
    if(xs.isEmpty) {
      meanRawPerDecile.add(double.nan);
      varRawPerDecile.add(double.nan);
      meanLnPerDecile.add(double.nan);
      varLnPerDecile.add(double.nan);
      continue;
    }
    meanRawPerDecile.add(xs.average);
    varRawPerDecile.add(populationVariance(xs));
    meanLnPerDecile.add(decileLn[d].average);
    varLnPerDecile.add(populationVariance(decileLn[d]));
  }

  final w = nColumnLabel.length > 12 ? nColumnLabel.length : 12;
  print("Decile | ${nColumnLabel.padRight(w)} | mean $valueLabel | var $valueLabel | mean ln | var ln");
  for(var d = 0; d < 10; d++) {
    print(
      "${d + 1}".padRight(6)
          + "| ${ns[d].toString().padLeft(w)}"
          + " | ${meanRawPerDecile[d].toStringAsFixed(6)}"
          + " | ${varRawPerDecile[d].toStringAsFixed(6)}"
          + " | ${meanLnPerDecile[d].toStringAsFixed(6)}"
          + " | ${varLnPerDecile[d].toStringAsFixed(6)}",
    );
  }

  var rRaw = pearsonCorrelation(meanRawPerDecile, varRawPerDecile);
  var rLn = pearsonCorrelation(meanLnPerDecile, varLnPerDecile);
  print("");
  print("Pearson r (decile pooled mean vs var, raw scale): ${rRaw?.toStringAsFixed(6) ?? "n/a"}");
  print("Pearson r (decile pooled mean ln vs var ln): ${rLn?.toStringAsFixed(6) ?? "n/a"}");
}

Future<void> _writeQqCsv(
  List<double> lnSample, {
  required String csvPath,
  required String sampleColumnHeader,
  required String sectionTitle,
}) async {
  print("=== $sectionTitle ===");
  if(lnSample.length < 10) {
    print("Not enough ln values (${lnSample.length}) for Q–Q.");
    return;
  }

  var sorted = [...lnSample]..sort();
  var n = sorted.length;
  var out = StringBuffer();
  out.writeln("$sampleColumnHeader,theoretical_normal_quantile");

  for(var i = 0; i < n; i++) {
    var p = (i + 0.5) / n;
    var z = Normal.quantile(p);
    out.writeln("${sorted[i]},$z");
  }

  var file = File(csvPath);
  await file.writeAsString(out.toString());
  print("Wrote $csvPath ($n rows). Plot $sampleColumnHeader vs theoretical_normal_quantile.");
}

void _printSkewnessSummary(List<double> perStageSkews, {required String sectionTitle}) {
  print("=== $sectionTitle ===");
  if(perStageSkews.isEmpty) {
    print("No skew samples.");
    return;
  }
  var s = [...perStageSkews]..sort();
  double q(double p) {
    var idx = (p * (s.length - 1)).round().clamp(0, s.length - 1);
    return s[idx];
  }

  print("Samples (instances): ${s.length}");
  print("Mean skewness: ${s.average.toStringAsFixed(6)}");
  print("Min / p25 / median / p75 / max: "
      "${s.first.toStringAsFixed(4)} / "
      "${q(0.25).toStringAsFixed(4)} / "
      "${q(0.5).toStringAsFixed(4)} / "
      "${q(0.75).toStringAsFixed(4)} / "
      "${s.last.toStringAsFixed(4)}");
}

double populationVariance(List<double> xs) {
  if(xs.isEmpty) {
    return double.nan;
  }
  var m = xs.average;
  return xs.map((x) => (x - m) * (x - m)).average;
}

double? pearsonCorrelation(List<double> xs, List<double> ys) {
  if(xs.length != ys.length) {
    return null;
  }
  final pairs = <(double, double)>[];
  for(var i = 0; i < xs.length; i++) {
    if(xs[i].isNaN || ys[i].isNaN) {
      continue;
    }
    pairs.add((xs[i], ys[i]));
  }
  if(pairs.length < 2) {
    return null;
  }
  var mx = pairs.map((e) => e.$1).average;
  var my = pairs.map((e) => e.$2).average;
  double cov = 0, vx = 0, vy = 0;
  for(var p in pairs) {
    var dx = p.$1 - mx;
    var dy = p.$2 - my;
    cov += dx * dy;
    vx += dx * dx;
    vy += dy * dy;
  }
  if(vx == 0 || vy == 0) {
    return null;
  }
  return cov / sqrt(vx * vy);
}

/// Third standardized moment (Fisher–Pearson skewness), same formula as [OpenStyleAnalysisCommand._calculateSkewness].
double fisherPearsonSkewness(List<double> data) {
  if(data.length < 3) {
    return double.nan;
  }
  var mean = data.average;
  var stdDev = sqrt(populationVariance(data));
  if(stdDev == 0.0) {
    return 0.0;
  }
  var sum = 0.0;
  for(var value in data) {
    var diff = (value - mean) / stdDev;
    sum += diff * diff * diff;
  }
  return sum / data.length;
}
