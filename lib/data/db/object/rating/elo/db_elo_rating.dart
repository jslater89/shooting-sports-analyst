import 'package:floor/floor.dart';
import 'package:uspsa_result_viewer/data/db/object/rating/rating_event.dart';
import 'package:uspsa_result_viewer/data/db/object/rating/shooter_rating.dart';
import 'package:uspsa_result_viewer/data/db/project/project_db.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/elo/elo_shooter_rating.dart';

@Entity(tableName: "eloRatings")
class DbEloRating extends RatingExtension {
  // TODO: rowid? entrynumber?
  @primaryKey
  int parentId;

  double rating;
  double variance;

  DbEloRating({
    required this.parentId,
    required this.rating,
    required this.variance,
  });

  static Future<DbEloRating> serialize(EloShooterRating rating, DbShooterRating dbRating, ProjectStore store) async {
    var dbEloRating = DbEloRating(
      parentId: dbRating.entryNumber,
      rating: rating.rating,
      variance: rating.variance,
    );
    
    await store.eloRatings.saveRating(dbEloRating);
    return dbEloRating;
  }
}

@dao
abstract class EloRatingDao {
  @Query("SELECT * FROM eloRatings WHERE parentId = :ratingId")
  Future<DbEloRating?> extensionForRating(int ratingId);

  @Query("SELECT * FROM eloRatingEvents WHERE parentId = :eventId")
  Future<List<DbEloEvent>> extensionForEvent(int eventId);

  @insert
  Future<int> saveRating(DbEloRating rating);

  @insert
  Future<int> saveEvent(DbRatingEvent rating);
}

@Entity(tableName: "eloRatingEvents")
class DbEloEvent extends RatingEventExtension {
  @primaryKey
  int parentId;

  double ratingChange;
  double oldRating;
  double baseK;
  double effectiveK;
  double error;

  DbEloEvent({
    required this.parentId,
    required this.ratingChange,
    required this.oldRating,
    required this.baseK,
    required this.effectiveK,
    required this.error,
  });
}