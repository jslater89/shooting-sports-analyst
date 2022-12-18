
import 'package:floor/floor.dart';
import 'package:uspsa_result_viewer/data/model.dart';

@Entity(tableName: "ratingEvents")
class DbRatingEvent {
  @PrimaryKey(autoGenerate: true)
  int? id;

  int ratingId;
  int matchId;
  int? stageId;

  // TODO: score values

  String infoKeys;
  String infoValues;

  static const separator = "|.|";

  DbRatingEvent({
    this.id,
    required this.ratingId,
    required this.matchId,
    this.stageId,
    required this.infoKeys,
    required this.infoValues,
  });
}

abstract class RatingEventExtension {
  int get parentId;
}