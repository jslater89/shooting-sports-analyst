import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';

class ProjectMigrationResult {
  DbRatingProject project;
  List<String> failedMatchIds;

  ProjectMigrationResult({
    required this.project,
    required this.failedMatchIds,
  });
}
