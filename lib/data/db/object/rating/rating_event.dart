
import 'package:floor/floor.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/ranking/rating_history.dart';

abstract class DbRatingEvent {
  String memberNumber;
  int projectId;
  RaterGroup group;
  String matchId;
  int stageId;

  // TODO: score values

  String infoKeys;
  String infoValues;

  static const separator = "|.|";

  DbRatingEvent({
    required this.memberNumber,
    required this.projectId,
    required this.group,
    required this.matchId,
    this.stageId = -1,
    required this.infoKeys,
    required this.infoValues,
  });
}