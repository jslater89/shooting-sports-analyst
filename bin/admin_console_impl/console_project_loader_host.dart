import "package:dart_console/dart_console.dart";
import "package:shooting_sports_analyst/console/repl.dart";
import "package:shooting_sports_analyst/data/ranking/project_loader.dart";
import "package:shooting_sports_analyst/util.dart";

RatingProjectLoaderHost consoleRatingProjectLoaderHost(Console console) {
  int lastProgress = -1;
  int lastMaxProgress = -1;
  int tickAccumulator = 0;
  String? lastGroupName;

  return RatingProjectLoaderHost(
    progressCallback: ({
      required int progress,
      required int total,
      required LoadingState state,
      String? eventName,
      String? groupName,
      int? subProgress,
      int? subTotal,
    }) async {
      if(progress < 0 || total < 0) {
        return;
      }

      String subtotalString = "";
      if(subProgress != null && subTotal != null) {
        subtotalString = " sub: $subProgress of $subTotal";
      }

      if(lastMaxProgress < 0) {
        lastMaxProgress = total;
        lastProgress = progress;
        tickAccumulator = 0;
        console.print("State: ${state.label} ${progress} of ${total} $subtotalString ${groupName ?? ""} ${eventName ?? ""} ");
      }

      if(progress < lastProgress) {
        tickAccumulator = 0;
        console.print("State: ${state.label} ${progress} of ${total} $subtotalString ${groupName ?? ""} ${eventName ?? ""} ");
      }

      lastProgress = progress;
      lastMaxProgress = total;

      tickAccumulator++;
      if(tickAccumulator % 10 == 0 || lastGroupName != groupName) {
        console.print("State: ${state.label} ${progress} of ${total} $subtotalString ${groupName ?? ""} ${eventName ?? ""} ");
      }
      lastGroupName = groupName;
    },
    deduplicationCallback: (group, deduplicationResult) async {
      console.print("Detected deduplication, ignoring");
      for(var collision in deduplicationResult) {
        console.print("Collision: ${collision.deduplicatorName}, ${collision.memberNumbers.keys.join(", ")}");
        console.print("Causes: ${collision.causes.map((e) => e.runtimeType).join(", ")}");
        console.print("Proposed Actions: ${collision.proposedActions.map((e) => e.runtimeType).join(", ")}");
        console.print("");
      }
      return Result.ok([]);
    },
    unableToAppendCallback: (lastUsedMatches, newMatches) async {
      console.print("Unable to append, recalculating");
      return true;
    },
    fullRecalculationRequiredCallback: () async {
      console.print("Full recalculation required, recalculating");
      return true;
    },
  );
}
