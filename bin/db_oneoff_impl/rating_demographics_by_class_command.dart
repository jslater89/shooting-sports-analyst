import "package:collection/collection.dart";
import "package:dart_console/dart_console.dart";
import "package:shooting_sports_analyst/console/repl.dart";
import "package:shooting_sports_analyst/data/database/analyst_database.dart";
import "package:shooting_sports_analyst/data/database/match/rating_project_database.dart";
import "package:shooting_sports_analyst/data/database/schema/ratings.dart";
import "package:shooting_sports_analyst/data/database/schema/ratings/shooter_rating.dart";
import "package:shooting_sports_analyst/data/ranking/raters/latentlog/latent_log_rater.dart";
import "package:shooting_sports_analyst/data/ranking/raters/latentlog/latent_log_rating_event.dart";

import "base.dart";

const String kDefaultLlrProjectName = "L2s Main LLR";

class RatingDemographicsByClassCommand extends DbOneoffCommand {
  RatingDemographicsByClassCommand(AnalystDatabase db) : super(db);

  @override
  final String key = "RDC";

  @override
  final String title = "Rating Demographics by Class (LLR)";

  @override
  Future<void> executor(Console console, List<MenuArgumentValue> arguments) async {
    await _run(db, console, projectName: kDefaultLlrProjectName);
  }
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

  final algorithm = project.settings.algorithm;
  if (algorithm is! LatentLogRater) {
    console.print(
      "Project $projectName is not a Latent Log project. "
      "This command requires Latent Log variance event data.",
    );
    return;
  }

  if (!project.dbGroups.isLoaded) {
    await project.dbGroups.load();
  }

  final allRatings = <DbShooterRating>[];
  for (final group in project.groups) {
    final ratingsRes = project.getRatingsSync(group);
    if (ratingsRes.isErr()) {
      console.print("Skipping ${group.name}; failed to load ratings.");
      continue;
    }
    allRatings.addAll(ratingsRes.unwrap());
  }

  if (allRatings.isEmpty) {
    console.print("No ratings found in project $projectName.");
    return;
  }

  final ratingsByClass = <String, List<DbShooterRating>>{};
  for (final rating in allRatings) {
    final className = rating.lastClassificationName;
    if (className == null || className.isEmpty) {
      continue;
    }
    ratingsByClass.putIfAbsent(className, () => []).add(rating);
  }

  final populationMean = allRatings.map((r) => r.rating).average;

  console.print("Project: $projectName");
  console.print("Population mean rating: ${populationMean.toStringAsFixed(4)}");
  console.print("");
  console.print(
    "Class                     N    AvgVariance@2ev    Q1         Mean       Q3         StartRating",
  );
  console.print(
    "-----------------------------------------------------------------------------------------------",
  );

  final sortedClassNames = ratingsByClass.keys.sorted();
  for (final className in sortedClassNames) {
    final classRatings = ratingsByClass[className]!;
    final classRatingValues = classRatings.map((r) => r.rating).toList()..sort();
    if (classRatingValues.isEmpty) {
      continue;
    }

    final classMean = classRatingValues.average;
    final q1 = _percentile(classRatingValues, 0.25);
    final q3 = _percentile(classRatingValues, 0.75);

    final bracketsPopulationMean =
        (q1 <= populationMean && populationMean <= q3) ||
        (q3 <= populationMean && populationMean <= q1);

    final startRating = bracketsPopulationMean
        ? classMean
        : _nearestTo(
            target: populationMean,
            a: q1,
            b: q3,
            tieBreak: classMean,
          );

    final earlyVariances = <double>[];
    for (final rating in classRatings) {
      if (rating.length <= 0) {
        continue;
      }

      final eventTarget = rating.length == 1 ? 1 : 2;
      final events = db.getRatingEventsForSync(
        rating,
        limit: eventTarget,
        order: Order.ascending,
      );
      if (events.length < eventTarget) {
        continue;
      }

      final targetEvent = events[eventTarget - 1];
      final wrapped = LatentLogRatingEvent.wrap(
        targetEvent,
        settings: algorithm.settings,
      );
      earlyVariances.add(wrapped.newVariance);
    }

    final averageVariance = earlyVariances.isEmpty ? double.nan : earlyVariances.average;
    final varianceText = averageVariance.isNaN
        ? "(n/a)".padLeft(16)
        : averageVariance.toStringAsFixed(6).padLeft(16);

    console.print(
      "${className.padRight(24)} "
      "${classRatings.length.toString().padLeft(4)} "
      "$varianceText    "
      "${q1.toStringAsFixed(4).padLeft(8)}   "
      "${classMean.toStringAsFixed(4).padLeft(8)}   "
      "${q3.toStringAsFixed(4).padLeft(8)}   "
      "${startRating.toStringAsFixed(4).padLeft(10)}",
    );
  }
}

double _percentile(List<double> sortedValues, double percentile) {
  if (sortedValues.isEmpty) {
    return 0.0;
  }
  if (sortedValues.length == 1) {
    return sortedValues.first;
  }

  final clamped = percentile.clamp(0.0, 1.0);
  final position = (sortedValues.length - 1) * clamped;
  final lowerIndex = position.floor();
  final upperIndex = position.ceil();

  if (lowerIndex == upperIndex) {
    return sortedValues[lowerIndex];
  }

  final lowerValue = sortedValues[lowerIndex];
  final upperValue = sortedValues[upperIndex];
  final weight = position - lowerIndex;
  return lowerValue + (upperValue - lowerValue) * weight;
}

double _nearestTo({
  required double target,
  required double a,
  required double b,
  required double tieBreak,
}) {
  final da = (a - target).abs();
  final db = (b - target).abs();

  if (da < db) {
    return a;
  }
  if (db < da) {
    return b;
  }
  return tieBreak;
}
