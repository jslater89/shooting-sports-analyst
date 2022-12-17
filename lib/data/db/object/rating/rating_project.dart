import 'package:floor/floor.dart';
import 'package:uspsa_result_viewer/data/db/object/match/match.dart';
import 'package:uspsa_result_viewer/data/db/project/project_db.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/ranking/project_manager.dart';
import 'package:uspsa_result_viewer/data/ranking/rating_history.dart';

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

  static Future<DbRatingProject> serialize(RatingHistory history, RatingProject settings, ProjectStore store) async {
    var dbProject = DbRatingProject(name: settings.name, settings: settings.toJson());
    int id = await store.projects.save(dbProject);
    dbProject.id = id;

    var matchesToDbIds = <PracticalMatch, int>{};
    for(var match in history.allMatches) {
      // check if present in match DB using PS IDs; if not, save
      var dbMatch = await store.matches.byPractiscoreId(match.practiscoreId);
      if(dbMatch == null) {
        dbMatch = await DbMatch.serialize(match, store);
      }
      matchesToDbIds[match] = dbMatch.id!;

      // create match-project DB item
      await store.projects.createLinkBetween(dbProject, dbMatch);
    }

    for(var group in history.groups) {
      // for each group, save ratings and rating events
      var rater = history.raterFor(history.allMatches.last, group);


    }

    return dbProject;
  }
}

@dao
abstract class RatingProjectDao {
  @insert
  Future<int> save(DbRatingProject project);

  @insert
  Future<int> saveLink(DbRatingProjectMatch match);

  Future<int> createLinkBetween(DbRatingProject project, DbMatch match) {
    return saveLink(DbRatingProjectMatch(projectId: project.id!, matchId: match.id!));
  }
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