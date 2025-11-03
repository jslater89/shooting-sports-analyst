import 'package:collection/collection.dart';
import 'package:dart_console/src/console.dart';
import 'package:shooting_sports_analyst/console/labeled_progress_bar.dart';
import 'package:shooting_sports_analyst/console/repl.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/match/hydrated_cache.dart';
import 'package:shooting_sports_analyst/data/database/match/rating_project_database.dart';
import 'package:shooting_sports_analyst/util.dart';

import 'base.dart';

class SpeedAccuracyBifectaCommand extends DbOneoffCommand {
  SpeedAccuracyBifectaCommand(AnalystDatabase db) : super(db);

  @override
  Future<void> executor(Console console, List<MenuArgumentValue> arguments) async {
    var project = await db.getRatingProjectByName("L2s Main");
    if(project == null) {
      console.print("Project not found");
      return;
    }
    var groups = await project.getGroups();
    if(groups.isErr()) {
      console.print("Error getting groups: ${groups.unwrapErr()}");
      return;
    }
    var groupsList = groups.unwrap();
    var matchPointers = project.matchPointers;
    int bifectaCount = 0;
    int matchGroupCount = 0;
    List<String> bifectas = [];
    var matchProgressBar = LabeledProgressBar(maxValue: matchPointers.length, initialLabel: "Processing matches...", canHaveErrors: true);
    for(var matchPointer in matchPointers) {
      var match = await db.getMatchByAnySourceId(matchPointer.sourceIds);
      if(match == null) {
        matchProgressBar.error("Match not found: ${matchPointer.sourceIds}");
        continue;
      }
      var hydratedMatchRes = await HydratedMatchCache().get(match);
      if(hydratedMatchRes.isErr()) {
        matchProgressBar.error("Error hydrating match: ${hydratedMatchRes.unwrapErr()}");
        continue;
      }
      var hydratedMatch = hydratedMatchRes.unwrap();
      var availablePoints = hydratedMatch.stages.map((s) => s.maxPoints).sum;
      matchProgressBar.tick("${match.eventName} (${bifectaCount})");
      for(var group in groupsList) {
        var scores = hydratedMatch.getScoresFromFilters(group.filters);
        if(scores.length < 20) {
          // matchProgressBar.error("Not enough scores for group: ${group.displayName ?? group.name}");
          continue;
        }

        var firstPlace = scores.entries.firstWhereOrNull((e) => e.value.place == 1);
        if(firstPlace == null) {
          matchProgressBar.error("No first place for group: ${group.displayName ?? group.name}");
          continue;
        }

        matchGroupCount++;
        var firstPlaceTotalPoints = firstPlace.value.total.points;
        var firstPlaceTime = firstPlace.value.total.finalTime;

        bool hasBifecta = true;
        for(var s in scores.entries) {
          if(s.value.place == 1) {
            continue;
          }

          if(!s.value.isComplete) {
            continue;
          }

          if(s.value.total.points > firstPlaceTotalPoints) {
            hasBifecta = false;
            break;
          }

          if(s.value.total.finalTime < firstPlaceTime) {
            hasBifecta = false;
            break;
          }
        }

        if(hasBifecta) {
          var pointsRatio = firstPlaceTotalPoints / availablePoints;
          var bifectaString = "${match.eventName} - ${firstPlace.key.name} (${group.displayName ?? group.name}) - ${pointsRatio.asPercentage(includePercent: true)} - ${firstPlaceTime.toStringAsFixed(2)}s";
          matchProgressBar.error(bifectaString);
          bifectas.add(bifectaString);
          bifectaCount++;
        }
      }
    }
    matchProgressBar.complete();
    console.print("Bifecta count: $bifectaCount");
    console.print("Match group count: $matchGroupCount");
    console.print("Bifecta percentage: ${(bifectaCount / matchGroupCount).asPercentage(includePercent: true)}");
    for(var bifecta in bifectas) {
      console.print(bifecta);
    }
  }

  @override
  String get key => "SAB";

  @override
  String get title => "Speed Accuracy Bifecta";

}
