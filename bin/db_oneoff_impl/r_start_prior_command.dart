import "package:dart_console/dart_console.dart";
import "package:shooting_sports_analyst/console/repl.dart";
import "package:shooting_sports_analyst/data/database/analyst_database.dart";
import "package:shooting_sports_analyst/data/database/match/rating_project_database.dart";

import "base.dart";

class RStartPriorCommand extends DbOneoffCommand {
  RStartPriorCommand(AnalystDatabase db) : super(db);

  @override
  final String key = "RSP";

  @override
  final String title = "Latent Log R_start Prior";

  @override
  Future<void> executor(Console console, List<MenuArgumentValue> arguments) async {
    final projects = [(await db.getRatingProjectByName("L2s Main LLR"))!];
    double innovationSum = 0.0;
    int innovationCount = 0;
    int ratingsSeen = 0;
    int ratingsWithEvents = 0;
    int ratingsWithInnovation = 0;

    for (final project in projects) {
      if (!project.dbGroups.isLoaded) {
        await project.dbGroups.load();
      }
      for (final group in project.dbGroups) {
        final ratingsRes = await project.getRatings(group);
        if (ratingsRes.isErr()) {
          console.print(
            "Error getting ratings for project ${project.name}, group ${group.name}: ${ratingsRes.unwrapErr()}",
          );
          continue;
        }

        final ratings = ratingsRes.unwrap();
        for (final rating in ratings) {
          ratingsSeen++;

          if (!rating.events.isLoaded) {
            await rating.events.load();
          }
          if (rating.events.isEmpty) {
            continue;
          }
          ratingsWithEvents++;

          final events = rating.events.toList();
          if (events.isEmpty) {
            continue;
          }
          events.sort((a, b) => a.date.compareTo(b.date));
          final firstEvent = events.first;

          double? innovation;
          for (final info in firstEvent.infoData) {
            if (info.name == "innovation") {
              innovation = info.doubleValue;
              break;
            }
          }
          if (innovation == null) {
            continue;
          }

          ratingsWithInnovation++;
          innovationCount++;
          innovationSum += innovation;
        }
      }
    }

    if (innovationCount == 0) {
      console.print(
        "No initial innovation values found in first events across all rating groups.",
      );
      console.print("Ratings scanned: $ratingsSeen");
      console.print("Ratings with events: $ratingsWithEvents");
      return;
    }

    final meanInnovation = innovationSum / innovationCount;
    console.print("Initial innovation arithmetic mean: ${meanInnovation.toStringAsFixed(6)}");
    console.print("Initial innovation samples: $innovationCount");
    console.print("Ratings scanned: $ratingsSeen");
    console.print("Ratings with events: $ratingsWithEvents");
    console.print("Ratings with first-event innovation: $ratingsWithInnovation");
  }
}
