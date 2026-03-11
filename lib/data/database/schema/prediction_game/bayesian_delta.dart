
import 'package:isar_community/isar.dart';
import 'package:shooting_sports_analyst/data/database/schema/db_entities.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/prediction_set.dart';
import 'package:shooting_sports_analyst/data/database/schema/prediction_game/prediction_game.dart';
import 'package:shooting_sports_analyst/data/database/schema/prediction_game/wager.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/prediction_game/bayesian_odds/config.dart';

part 'bayesian_delta.g.dart';

@collection
class BayesianDelta with DbShooterRatingEntity {
  Id id = Isar.autoIncrement;

  @override
  final group = IsarLink<RatingGroup>();

  @override
  @Index()
  @Index(name: 'memberNumberAndSetId', composite: [CompositeIndex('predictionSetId')])
  String memberNumber;

  @Index(type: IndexType.value)
  List<String> knownMemberNumbers = [];

  @override
  final project = IsarLink<DbRatingProject>();

  @override
  final rating = IsarLink<DbShooterRating>();

  double delta;

  List<double> betWeights = [];

  @Index()
  /// The prediction set ID for which this delta is valid.
  int predictionSetId;

  /// The prediction set for which this delta is valid.
  final predictionSet = IsarLink<PredictionSet>();

  /// The type of prediction for which this delta is valid.
  ///
  /// Valid types are place and percentage. (Spread predictions
  /// are decomposed into percentage signals.)
  @enumerated
  DbPredictionType type;

  @Index()
  int gameId;
  final game = IsarLink<PredictionGame>();

  /// The wagers that were used to calculate this delta.
  final contributingWagers = IsarLinks<DbWager>();

  /// The IDs of the wagers that were used to calculate this delta,
  /// indexed for fast lookup. (This permits fast lookup of delta records
  /// by wager ID without a backlink.)
  @Index(type: IndexType.value)
  List<int> contributingWagerIds = [];

  /// The timestamp of the most recent bet included in this delta computation.
  DateTime lastBetTimestamp;

  /// The timestamp of the computation of this delta.
  DateTime computedAt;

  /// The hash of the configuration used to calculate this delta.
  ///
  /// This is used to identify deltas that were calculated with the same configuration.
  ///
  int configHash;

  /// Internal constructor for Isar.
  ///
  /// Use [create] to create a new delta.
  BayesianDelta({
    required this.memberNumber,
    this.knownMemberNumbers = const [],
    required this.delta,
    required this.type,
    required this.lastBetTimestamp,
    required this.computedAt,
    required this.predictionSetId,
    required this.configHash,
    required this.betWeights,
    required this.gameId,
  });

  /// Create a new delta, setting up initial links values and ID/member number
  /// properties from the provided values.
  BayesianDelta.create({
    required this.memberNumber,
    this.knownMemberNumbers = const [],
    required DbRatingProject project,
    required DbShooterRating rating,
    required RatingGroup group,
    required this.delta,
    required this.type,
    required List<DbWager> contributingWagers,
    required this.lastBetTimestamp,
    required this.computedAt,
    required PredictionSet predictionSet,
    required PredictionGame game,
    required BayesianOddsConfig config,
    required this.betWeights,
  }) :
    contributingWagerIds = contributingWagers.map((w) => w.id).toList(),
    predictionSetId = predictionSet.id,
    gameId = game.id,
    configHash = config.configHash {
      this.group.value = group;
      this.project.value = project;
      this.rating.value = rating;
      this.contributingWagers.addAll(contributingWagers);
      this.predictionSet.value = predictionSet;
      this.memberNumber = rating.memberNumber;
      this.knownMemberNumbers = [...rating.knownMemberNumbers];
      this.game.value = game;
    }

  void addContributingWager(DbWager wager) {
    contributingWagers.add(wager);
    contributingWagerIds.add(wager.id);
  }

  void removeContributingWager(DbWager wager) {
    contributingWagers.remove(wager);
    contributingWagerIds.remove(wager.id);
  }
}