import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/util.dart';

final _log = SSALogger("MatchPointerDeduplicator");

/// Given a list of match pointers, remove any duplicates. Duplicate match pointers have
/// the same source code and any overlapping source IDs.
List<MatchPointer> deduplicateMatchPointers(List<MatchPointer> matchPointers) {
  Map<String, MatchPointer> pointersBySourceIds = {};
  List<MatchPointer> uniquePointers = [];
  String key(String sourceCode, String sourceId) {
    return "${sourceCode}:${sourceId}";
  }

  for(var matchPointer in matchPointers) {
    MatchPointer? duplicate = null;
    for(var sourceId in matchPointer.sourceIds) {
      final k = key(matchPointer.sourceCode, sourceId);
      if(pointersBySourceIds.containsKey(k)) {
        // If there's already a match pointer with this source ID and source code, it's a duplicate.
        duplicate = pointersBySourceIds[k];
        break;
      }
    }

    // If there are no duplicates, add this match pointer to the map.
    if(duplicate == null) {
      for(var sourceId in matchPointer.sourceIds) {
        final k = key(matchPointer.sourceCode, sourceId);
        pointersBySourceIds[k] = matchPointer;
      }
      uniquePointers.add(matchPointer);
    }
    else {
      // If there is a duplicate, keep the duplicate and union the source IDs onto it.
      final sourceIds = duplicate.sourceIds.union(matchPointer.sourceIds).toList();
      duplicate.sourceIds = sourceIds;
    }
  }

  final deduplicatedList = uniquePointers;
  if(matchPointers.length != deduplicatedList.length) {
    _log.i("Deduplicated ${matchPointers.length} match pointers to ${deduplicatedList.length} unique match pointers");
  }

  return deduplicatedList;
}