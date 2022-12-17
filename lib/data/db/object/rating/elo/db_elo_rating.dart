import 'package:floor/floor.dart';
import 'package:uspsa_result_viewer/data/db/object/rating/rating_event.dart';
import 'package:uspsa_result_viewer/data/db/object/rating/shooter_rating.dart';

@Entity(tableName: "eloRatings")
class DbEloRating extends RatingExtension {
  @primaryKey
  int parentId;

  double rating;
  double variance;

  DbEloRating({
    required this.parentId,
    required this.rating,
    required this.variance,
  });
}

@dao
abstract class EloRatingDao {
  @Query("SELECT * FROM eloRatings WHERE parentId = :ratingId")
  Future<DbEloRating?> extensionForRating(int ratingId);

  @Query("SELECT * FROM eloRatingEvents WHERE parentId = :eventId")
  Future<List<DbEloEvent>> extensionForEvent(int eventId);
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