/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

/*
Section	Mostly measures
Duration-X
Development among committed shooters (field-adjusted windows)

Trajectories
Shape of multi-year field-adjusted paths

Tenure vs rating
Cross-section volume ↔ level (selection + skill)

Error / connectivity
Model confidence / linkage vs volume

Early vs career
Selection at debut

Match mix
Where people shoot vs volume

Cohort early rating
Entry era vs starting level

Inactive / aged
Stale ratings vs mean reversion

Era × tenure bins
Vintage × experience interaction

Longitudinal age
Learning curve vs field among year-by-year survivors

Retention deciles
Staying vs early rating
*/

/// Field-adjusted career metrics, tenure/rating analyses, symmetrical trajectories, and optional two-project contrast.
///
/// Launch (non-interactive):
/// `dart run bin/db_oneoffs.dart CFA [projectName] [durationYears] [minMatches] [minYearsTrajectory] [minDataYear] [compareProject] [csvPath] [trajectoryCsvPath]`

import "package:collection/collection.dart";
import "package:dart_console/dart_console.dart";
import "package:shooting_sports_analyst/console/repl.dart";
import "package:shooting_sports_analyst/data/database/analyst_database.dart";
import "package:shooting_sports_analyst/data/database/match/rating_project_database.dart";
import "package:shooting_sports_analyst/data/ranking/raters/latentlog/latent_log_rater.dart";

import "base.dart";
import "career_metrics_lib.dart";

const String kDefaultCareerProjectName = "L2s Main LLR";

class CareerFieldAdjustedMetricsCommand extends DbOneoffCommand {
  CareerFieldAdjustedMetricsCommand(AnalystDatabase db) : super(db);

  @override
  final String key = "CFA";

  @override
  final String title = "Career Metrics (Field-Adjusted)";

  @override
  String? get description =>
      "Per rating group: field-adjusted trajectories (symmetrical up/down shapes), tenure–rating "
      "bins, early-rating vs career, cohort inflation, inactive/aged gap, survival, "
      "longitudinal quantiles; optional LOCO contrast; optional summary CSV and trajectory long CSV for plots.";

  @override
  List<MenuArgument> get arguments => [
        StringMenuArgument(
          label: "Project name",
          defaultValue: kDefaultCareerProjectName,
          description: "Primary rating project (e.g. L2s Main LLR).",
        ),
        IntMenuArgument(
          label: "Duration years X",
          defaultValue: 3,
          description: "Tenure window: compare first active calendar year to year first+X-1.",
        ),
        IntMenuArgument(
          label: "Min matches",
          defaultValue: 8,
          description: "Minimum distinct matches for duration-X eligibility.",
        ),
        IntMenuArgument(
          label: "Min years (trajectory)",
          defaultValue: 4,
          description: "Minimum distinct calendar years with ≥1 event for shape classification.",
        ),
        IntMenuArgument(
          label: "Min data year",
          defaultValue: 2018,
          description: "Ignore rating events strictly before this calendar year.",
        ),
        StringMenuArgument(
          label: "Compare project",
          defaultValue: "",
          description: "Optional second project for tenure/rating contrast (e.g. L2s Main LLR LOCO). Leave empty to skip.",
        ),
        StringMenuArgument(
          label: "CSV path",
          defaultValue: "",
          description: "Optional per-shooter summary CSV (one file, all groups).",
        ),
        StringMenuArgument(
          label: "Trajectory CSV path",
          defaultValue: "",
          description: "Optional long-format CSV (one row per shooter-year) for trajectory plots; see research/career-trajectories/.",
        ),
      ];

  @override
  Future<void> executor(Console console, List<MenuArgumentValue> arguments) async {
    final projectName = arguments.firstWhereOrNull((a) => a.argument.label == "Project name")?.getAs<String>().trim();
    final durationYears = arguments.firstWhereOrNull((a) => a.argument.label == "Duration years X")?.getAs<int>();
    final minMatches = arguments.firstWhereOrNull((a) => a.argument.label == "Min matches")?.getAs<int>();
    final minYearsTrajectory = arguments.firstWhereOrNull((a) => a.argument.label == "Min years (trajectory)")?.getAs<int>();
    final minDataYear = arguments.firstWhereOrNull((a) => a.argument.label == "Min data year")?.getAs<int>();
    final compareProject = arguments.firstWhereOrNull((a) => a.argument.label == "Compare project")?.getAs<String>().trim() ?? "";
    final csvPath = arguments.firstWhereOrNull((a) => a.argument.label == "CSV path")?.getAs<String>().trim() ?? "";
    final trajectoryCsvPath =
        arguments.firstWhereOrNull((a) => a.argument.label == "Trajectory CSV path")?.getAs<String>().trim() ?? "";

    if (projectName == null || projectName.isEmpty) {
      console.print("Missing project name.");
      return;
    }
    if (durationYears == null || durationYears < 1) {
      console.print("Duration years X must be ≥ 1.");
      return;
    }
    if (minMatches == null || minMatches < 1) {
      console.print("Min matches must be ≥ 1.");
      return;
    }
    if (minYearsTrajectory == null || minYearsTrajectory < 2) {
      console.print("Min years (trajectory) must be ≥ 2.");
      return;
    }
    if (minDataYear == null) {
      console.print("Missing min data year.");
      return;
    }

    await _runCareerFieldAdjustedMetrics(
      db,
      console,
      projectName: projectName,
      compareProjectName: compareProject.isEmpty ? null : compareProject,
      csvPath: csvPath.isEmpty ? null : csvPath,
      trajectoryCsvPath: trajectoryCsvPath.isEmpty ? null : trajectoryCsvPath,
      config: CareerMetricsConfig(
        minDataYear: minDataYear,
        durationYears: durationYears,
        minMatches: minMatches,
        minYearsTrajectory: minYearsTrajectory,
      ),
    );
  }
}

Future<void> _runCareerFieldAdjustedMetrics(
  AnalystDatabase db,
  Console console, {
  required String projectName,
  required String? compareProjectName,
  required String? csvPath,
  required String? trajectoryCsvPath,
  required CareerMetricsConfig config,
}) async {
  final project = await db.getRatingProjectByName(projectName);
  if (project == null) {
    console.print("Rating project not found: $projectName");
    return;
  }

  if (!project.dbGroups.isLoaded) {
    await project.dbGroups.load();
  }

  LatentLogRater? llrRater;
  if (project.settings.algorithm is LatentLogRater) {
    llrRater = project.settings.algorithm as LatentLogRater;
  }

  console.print("");
  console.print("Project: $projectName");
  if (compareProjectName != null) {
    console.print("Compare project: $compareProjectName");
  }
  if (csvPath != null) {
    console.print("CSV export: $csvPath");
  }
  if (trajectoryCsvPath != null) {
    console.print("Trajectory long CSV: $trajectoryCsvPath");
  }
  console.print(
    "Parameters: minDataYear=${config.minDataYear}, durationYears=${config.durationYears}, "
    "minMatches=${config.minMatches}, minYearsTrajectory=${config.minYearsTrajectory}",
  );
  console.print(
    "Field adjustment: end-of-year newRating − group median for that calendar year.",
  );
  console.print("");

  final allDatasets = <GroupCareerDataset>[];

  for (final group in project.groups) {
    final data = buildGroupCareerDataset(
      db: db,
      project: project,
      group: group,
      config: config,
      llrRater: llrRater,
    );
    allDatasets.add(data);
    printGroupCareerReports(console, data, config);
  }

  if (csvPath != null && allDatasets.any((d) => d.rows.isNotEmpty)) {
    writeAllCareerCsv(csvPath, allDatasets, projectName: projectName);
    console.print("Wrote ${allDatasets.fold<int>(0, (n, d) => n + d.rows.length)} shooter rows to $csvPath");
  }

  if (trajectoryCsvPath != null && allDatasets.any((d) => d.rows.isNotEmpty)) {
    writeCareerTrajectoryLongCsv(
      trajectoryCsvPath,
      allDatasets,
      projectName: projectName,
      llrRater: llrRater,
    );
    final rowCount = allDatasets.fold<int>(0, (n, d) {
      return n +
          d.rows
              .where((r) => r.activeYears.length >= 2)
              .fold<int>(0, (m, r) => m + r.activeYears.length);
    });
    console.print("Wrote $rowCount trajectory rows to $trajectoryCsvPath");
  }

  if (compareProjectName != null) {
    final compareProject = await db.getRatingProjectByName(compareProjectName);
    if (compareProject == null) {
      console.print("Compare project not found: $compareProjectName");
      return;
    }
    if (!compareProject.dbGroups.isLoaded) {
      await compareProject.dbGroups.load();
    }

    LatentLogRater? compareLlr;
    if (compareProject.settings.algorithm is LatentLogRater) {
      compareLlr = compareProject.settings.algorithm as LatentLogRater;
    }

    for (final primary in allDatasets) {
      final compareGroup = compareProject.groups.firstWhereOrNull(
        (g) => g.uiLabel == primary.groupLabel || g.name == primary.groupLabel,
      );
      if (compareGroup == null) {
        console.print("No matching compare group for ${primary.groupLabel}; skipping contrast.");
        continue;
      }
      final compareData = buildGroupCareerDataset(
        db: db,
        project: compareProject,
        group: compareGroup,
        config: config,
        llrRater: compareLlr,
      );
      printTwoProjectContrast(console, primary, compareData);
    }
  }

}
