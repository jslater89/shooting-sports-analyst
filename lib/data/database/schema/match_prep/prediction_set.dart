
import 'package:isar_community/isar.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/algorithm_prediction.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/match_prep.dart';
import 'package:shooting_sports_analyst/util.dart';

part 'prediction_set.g.dart';

/// A PredictionSet is a collection of predictions for a particular match prep.
///
/// Predictions may be run repeatedly over time. Prediction sets collect a single run of
/// predictions along with some light metadata about the run, so that a given set of predictions
/// can be reviewed after the fact (and after later predictions are run).
///
/// The id is a synthesis of the match prep id and the name of the prediction set.
@collection
class PredictionSet {

  PredictionSet({
    required this.matchPrepId,
    required this.name,
    required this.created,
    this.note,
  });

  PredictionSet.create({
    required MatchPrep matchPrep,
    required this.name,
    DateTime? created,
    this.note
  }) {
    this.matchPrep.value = matchPrep;
    this.matchPrepId = matchPrep.id;
    this.created = created ?? DateTime.now();
  }

  Id get id => combineHashList([matchPrepId.stableHash, name.stableHash]);

  /// The id of the [MatchPrep] that this prediction set belongs to.
  late int matchPrepId;

  /// The date and time the prediction set was created.
  late DateTime created;

  /// The name of the prediction set.
  String name;

  /// A note about the prediction set.
  String? note;

  /// The [MatchPrep] that this prediction set belongs to.
  @Backlink(to: 'predictionSets')
  final matchPrep = IsarLink<MatchPrep>();

  /// The algorithm predictions for this prediction set.
  final algorithmPredictions = IsarLinks<DbAlgorithmPrediction>();
}