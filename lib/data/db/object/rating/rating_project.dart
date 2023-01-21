import 'dart:convert';

import 'package:floor/floor.dart';
import 'package:uspsa_result_viewer/data/db/object/match/match.dart';
import 'package:uspsa_result_viewer/data/db/object/rating/elo/db_elo_rating.dart';
import 'package:uspsa_result_viewer/data/db/object/rating/rating_event.dart';
import 'package:uspsa_result_viewer/data/db/object/rating/rating_types.dart';
import 'package:uspsa_result_viewer/data/db/object/rating/shooter_rating.dart';
import 'package:uspsa_result_viewer/data/db/project/project_db.dart';
import 'package:uspsa_result_viewer/data/match_cache/match_cache.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/ranking/member_number_correction.dart';
import 'package:uspsa_result_viewer/data/ranking/project_manager.dart';
import 'package:uspsa_result_viewer/data/ranking/rater.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/elo/elo_shooter_rating.dart';
import 'package:uspsa_result_viewer/data/ranking/rating_history.dart';

@Entity(
  tableName: "ratingProjects",
)
class DbRatingProject {
  @PrimaryKey(autoGenerate: true)
  int? id;

  String name;

  /// Reproduced in the settings, but used to determine
  /// what ShooterRating/RatingEvent subclass to use
  RatingType algorithm;

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
    required this.algorithm,
    required this.settings,
  });

  static Future<DbRatingProject> serialize(RatingHistory history, RatingProject settings, ProjectStore store) async {
    var dbProject = DbRatingProject(name: settings.name, algorithm: RatingType.fromSettings(settings.settings), settings: settings.toJson());
    int id = await store.projects.save(dbProject);
    dbProject.id = id;

    var matchesToDbIds = <PracticalMatch, String>{};
    var dbLinks = <DbRatingProjectMatch>[];
    for(var match in history.allMatches) {
      // check if present in match DB using PS IDs; if not, save
      var dbMatch = await store.matches.byPractiscoreId(match.practiscoreId);
      if(dbMatch == null) {
        dbMatch = await DbMatch.serialize(match, store);
      }
      matchesToDbIds[match] = dbMatch.psId;

      // create match-project DB item
      dbLinks.add(store.projects.createLinkBetween(dbProject, dbMatch));
    }
    await store.projects.saveLinks(dbLinks);

    for(var group in history.groups) {
      // for each group, save member mappings, ratings, and rating events
      var mappings = <DbMemberNumberMapping>[];

      var rater = history.raterFor(history.allMatches.last, group);
      for(var mapping in rater.memberNumberMappings.entries) {
        if(mapping.key != mapping.value) {
          mappings.add(DbMemberNumberMapping(
              projectId: dbProject.id!, raterGroup: group, number: mapping.key, mapping: mapping.value
          ));
        }
      }
      await store.projects.saveMemberNumberMappings(mappings);

      // encountered numbers: all 'number' cols in mappings, plus all member numbers
      // in ratings.

      var ratings = <DbEloRating>[];
      var events = <DbEloEvent>[];
      for(var rating in rater.knownShooters.values) {
        switch(dbProject.algorithm) {
          case RatingType.elo:
            ratings.add(DbEloRating.convert(rating as EloShooterRating, dbProject, group));
            events.addAll(DbEloEvent.fromRating(rating, dbProject, group, matchesToDbIds));
            break;
          default: throw UnsupportedError("not yet implemented");
        }
      }

      await store.eloRatings.saveRatings(ratings);
      await store.eloRatings.saveEvents(events);
    }

    return dbProject;
  }

  Future<RatingHistory> deserialize(ProjectDatabase db) async {
    var project = RatingProject.fromJson(jsonDecode(this.settings));
    var dbMatches = await db.matches.byRatingProject(this.id!);

    var matches = await _loadMatchesIfNotLoaded(db, dbMatches);

    var history = RatingHistory(matches: matches, project: project);

    var raters = <RaterGroup, Rater>{};

    for(var group in project.settings.groups) {
      // Create a rater
      var r = Rater(
        matches: matches,
        ratingSystem: project.settings.algorithm,
        byStage: project.settings.byStage,
        filters: group.filters,
        dataCorrections: MemberNumberCorrectionContainer(),
      );

      // Load ratings, events, and member number mappings
      List<DbMemberNumberMapping> mappings = await db.projects.getMemberNumberMappings(this.id!, group);
      List<DbShooterRating> ratings = await db.eloRatings.ratingsForGroup(this.id!, group);
      Map<DbShooterRating, List<DbRatingEvent>> eventsByShooter = {};
      for(var rating in ratings) {
        var events = await db.eloRatings.eventsForMember(this.id!, group, rating.memberNumber);
        eventsByShooter[rating] = events;
      }

      r.deserializeFrom(mappings, ratings, eventsByShooter);

      // Add rater to project
      raters[group] = r;
    }

    history.loadRatings(raters);

    return history;
  }

  Future<List<PracticalMatch>> _loadMatchesIfNotLoaded(MatchStore db, List<DbMatch> dbMatches) async {
    await MatchCache().ready;

    List<PracticalMatch> matches = [];
    var cache = MatchCache();
    var inserted = false;
    for(var dbMatch in dbMatches) {
      var existing = cache.getMatchImmediate(dbMatch.psId);
      if(existing != null) {
        matches.add(existing);
        continue;
      }

      var match = await dbMatch.deserialize(db);
      matches.add(match);
      cache.insert(match);
      inserted = true;
    }

    if(inserted) cache.save();
    return matches;
  }
}

@dao
abstract class RatingProjectDao {
  @insert
  Future<int> save(DbRatingProject project);

  @insert
  Future<int> saveLink(DbRatingProjectMatch match);

  @insert
  Future<void> saveLinks(List<DbRatingProjectMatch> matches);

  DbRatingProjectMatch createLinkBetween(DbRatingProject project, DbMatch match) {
    return DbRatingProjectMatch(projectId: project.id!, matchId: match.psId);
  }

  @insert
  Future<void> saveMemberNumberMapping(DbMemberNumberMapping mapping);

  @insert
  Future<void> saveMemberNumberMappings(List<DbMemberNumberMapping> mapping);

  @Query("SELECT * FROM memberNumberMappings WHERE projectId = :projectId AND raterGroup = :group")
  Future<List<DbMemberNumberMapping>> getMemberNumberMappings(int projectId, RaterGroup group);
}

@Entity(tableName: "ratingProjects_matches")
class DbRatingProjectMatch {
  @PrimaryKey(autoGenerate: true)
  int? id;

  @ForeignKey(childColumns: ["projectId"], parentColumns: ["id"], entity: DbRatingProject, onDelete: ForeignKeyAction.cascade)
  int projectId;
  @ForeignKey(childColumns: ["matchId"], parentColumns: ["psId"], entity: DbMatch, onDelete: ForeignKeyAction.restrict)
  String matchId;

  DbRatingProjectMatch({
    this.id,
    required this.projectId,
    required this.matchId,
  });
}

/// Stores member number mappings for a given rater project/rater ID.
/// Only interesting mappings (i.e., not N->N) are saved.
///
/// Although, I think we can probably store this globally in the future...
@Entity(
  tableName: "memberNumberMappings",
  primaryKeys: [
    "projectId", "raterGroup", "number", "mapping",
  ],
  withoutRowid: true,
)
class DbMemberNumberMapping {
  int projectId;
  RaterGroup raterGroup;

  String number;
  String mapping;

  DbMemberNumberMapping({
    required this.projectId,
    required this.raterGroup,
    required this.number,
    required this.mapping,
  });
}