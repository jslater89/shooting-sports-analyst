import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';

List<RatingGroup> resolveRatingGroup(String groupUuid, DbRatingProject project) {
  if(!groupUuid.startsWith("uspsa-")) {
    groupUuid = "uspsa-$groupUuid";
  }
  var groups = project.groups.where((g) => g.uuid.startsWith(groupUuid)).toList();
  return groups.toList();
}
