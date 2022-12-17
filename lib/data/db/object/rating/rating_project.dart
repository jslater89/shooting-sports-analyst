import 'package:floor/floor.dart';

@Entity(
  tableName: "ratingProjects",
)
class DbRatingProject {
  @PrimaryKey(autoGenerate: true)
  int? id;

  String name;

  /// Contains the JSON representation of the settings used
  /// to create the project, which is easier to inflate.
  String settings;

  // deserializing:
  // 1. Load all of the matches, shooters, etc. from the project DB.
  //    We're doing it! One big database locally, and we'll serialize
  //    what we need to serialize when we want to export a project, and
  //    selectively import stuff from it, I guess.

  // 2. Use RatingProject to deserialize this.settings.
  // 3. Use the RatingProject to generate a RatingHistory, filling in the PracticalMatches
  //    by parsing the match IDs out of RatingProject's match URLs.
  // 4. Load raters.
  // 5.

  DbRatingProject({
    this.id,
    required this.name,
    required this.settings,
  });
}

@dao
abstract class RatingProjectDao {

}

@Entity(tableName: "ratingProjects_matches")
class DbRatingProjectMatch {
  @PrimaryKey(autoGenerate: true)
  int? id;

  @ForeignKey(childColumns: ["projectId"], parentColumns: ["id"], entity: DbRatingProject)
  int projectId;
  int matchId;

  DbRatingProjectMatch({
    this.id,
    required this.projectId,
    required this.matchId,
  });
}