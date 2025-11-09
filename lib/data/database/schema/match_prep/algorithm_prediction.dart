/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:isar_community/isar.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/db_entities.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/match_prep.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_settings.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_system.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/match_prediction.dart';
import 'package:shooting_sports_analyst/util.dart';

part 'algorithm_prediction.g.dart';

@collection
class DbAlgorithmPrediction with DbShooterRatingEntity {
  Id get id => combineHashList([projectId, matchPrepId, originalMemberNumber.stableHash]);

  final project = IsarLink<DbRatingProject>();
  @Backlink(to: 'algorithmPredictions')
  final matchPrep = IsarLink<MatchPrep>();
  int projectId;
  int matchPrepId;

  @Ignore()
  RatingSystem get algorithm => project.value!.settings.algorithm;

  @Ignore()
  RaterSettings get settings => algorithm.settings;

  double mean;

  double oneSigma;
  double twoSigma;
  double ciOffset;

  int lowPlace;
  int highPlace;
  int medianPlace;

  DbAlgorithmPrediction({
    required this.projectId,
    required this.matchPrepId,
    required this.mean,
    required this.oneSigma,
    required this.twoSigma,
    required this.ciOffset,
    required this.lowPlace,
    required this.highPlace,
    required this.medianPlace,
  });

  DbAlgorithmPrediction.fromHydrated(DbRatingProject project, MatchPrep matchPrep, AlgorithmPrediction prediction) :
    projectId = project.id,
    matchPrepId = matchPrep.id,
    mean = prediction.mean,
    oneSigma = prediction.oneSigma,
    twoSigma = prediction.twoSigma,
    ciOffset = prediction.ciOffset,
    lowPlace = prediction.lowPlace,
    highPlace = prediction.highPlace,
    medianPlace = prediction.medianPlace {
      this.rating.value = prediction.shooter.wrappedRating;
      this.project.value = project;
      this.group.value = prediction.shooter.group;
      this.originalMemberNumber = prediction.shooter.originalMemberNumber;
    }

  static List<DbAlgorithmPrediction> dehydrate(DbRatingProject project, MatchPrep matchPrep, List<AlgorithmPrediction> predictions) {
    return predictions.map((p) => DbAlgorithmPrediction.fromHydrated(project, matchPrep, p)).toList();
  }

  // TODO: Result<>
  AlgorithmPrediction? hydrate() {
    var dbRating = getShooterRatingSync(AnalystDatabase(), save: true);
    if(dbRating == null) {
      return null;
    }
    var wrapped = algorithm.wrapDbRating(dbRating);
    var prediction = AlgorithmPrediction(
      shooter: wrapped,
      mean: mean,
      sigma: oneSigma,
      ciOffset: ciOffset,
      settings: settings,
      algorithm: algorithm,
    );
    prediction.lowPlace = lowPlace;
    prediction.highPlace = highPlace;
    prediction.medianPlace = medianPlace;
    return prediction;
  }

  @override
  final group = IsarLink<RatingGroup>();

  @override
  String originalMemberNumber = "";

  @override
  final rating = IsarLink<DbShooterRating>();
}
