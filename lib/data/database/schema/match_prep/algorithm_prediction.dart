/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:isar_community/isar.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/db_entities.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/prediction_set.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_settings.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_system.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/match_prediction.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/shooter.dart';
import 'package:shooting_sports_analyst/util.dart';

part 'algorithm_prediction.g.dart';

/// A DbAlgorithmPrediction is a dehydrated [AlgorithmPrediction] for a particular shooter,
/// prediction set, and rating project. The id is a synthesis of the project id, prediction set id,
/// group uuid, and the shooter's original member number.
@collection
class DbAlgorithmPrediction with DbShooterRatingEntity {
  Id get id {
    if(groupUuid == null) {
      return combineHashList64([
        projectId,
        predictionSetId,
        memberNumber.stableHash,
        if(scoringGroupUuid != null) scoringGroupUuid!.stableHash
      ]);
    }
    else {
      return combineHashList64([
        projectId,
        predictionSetId,
        groupUuid!.stableHash,
        memberNumber.stableHash,
        if(scoringGroupUuid != null) scoringGroupUuid!.stableHash
      ]);
    }
  }

  final project = IsarLink<DbRatingProject>();

  @Backlink(to: 'algorithmPredictions')
  final predictionSet = IsarLink<PredictionSet>();

  /// The group in [predictionSet] where the rating backing this prediction can be
  /// found.
  @override
  final group = IsarLink<RatingGroup>();

  /// The UUID identifying [group] in the sport of [project].
  final String? groupUuid;

  /// If set, the group identifying the registrations against which this prediction
  /// was made/should be scored. Otherwise, [group] is assumed to be the scoring group.
  ///
  /// See [effectiveScoringGroup] for a convenience getter.
  final scoringGroup = IsarLink<RatingGroup>();

  /// The UUID identifying [scoringGroup] in the sport of [project].
  final String? scoringGroupUuid;

  /// The scoring group for this prediction: the group from which registrations were selected,
  /// and against which outcomes should be evaluated. Distinct from [group], which contains the
  /// rating used to generate predictions.
  ///
  /// i.e., if [group] is USPSA LO/CO and effectiveScoringGroup is USPSA CO, then this prediction
  /// should be displayed on a Carry Optics tab and evaluated only against CO competitors, but was
  /// generated against a set of combined LO/CO ratings.
  @ignore
  RatingGroup get effectiveScoringGroup => scoringGroup.value ?? group.value!;

  /// A member number that can locate the correct shooter rating for this prediction
  /// in [group].
  @override
  String memberNumber = "";

  @override
  final rating = IsarLink<DbShooterRating>();

  /// The id of the [DbRatingProject] that this prediction belongs to.
  int projectId;

  @Index()
  /// The id of the [PredictionSet] that this prediction belongs to.
  int predictionSetId;

  @Ignore()
  RatingSystem get algorithm => project.value!.settings.algorithm;

  @Ignore()
  RaterSettings get settings => algorithm.settings;

  /// The central performance in display terms. This may not
  /// strictly be a mean; for log-normal rating engines it
  /// might be the median around which the geometric standard
  /// deviation is defined.
  double mean;

  /// The central performance in display terms.
  @ignore double get displayCenter => mean;
  set displayCenter(double value) => mean = value;

  double oneSigma;
  double twoSigma;
  double ciOffset;

  int lowPlace;
  int highPlace;
  int medianPlace;

  /// The expected ratio of the performance to the winner.
  double? meanRatio;

  @ignore double? get expectedRatio => meanRatio;
  set expectedRatio(double? value) => meanRatio = value;

  double? oneSigmaRatio;
  double? shiftRatio;

  bool isLogNormal = false;
  double? logMean;
  double? logSigma;

  @ignore
  bool get hasRatioPredictions => meanRatio != null && oneSigmaRatio != null;

  double? get ratioCenter => meanRatio;
  double? get shiftedRatioCenter {
    if(meanRatio != null && shiftRatio != null) {
      return meanRatio! + shiftRatio!;
    }
    else if(meanRatio != null) {
      return meanRatio!;
    }
    else {
      return null;
    }
  }

  DbAlgorithmPrediction({
    required this.projectId,
    required this.predictionSetId,
    required this.groupUuid,
    required this.mean,
    required this.oneSigma,
    required this.twoSigma,
    required this.ciOffset,
    required this.lowPlace,
    required this.highPlace,
    required this.medianPlace,
    required this.meanRatio,
    required this.oneSigmaRatio,
    required this.shiftRatio,
    required this.isLogNormal,
    required this.logMean,
    required this.logSigma,
    required this.scoringGroupUuid,
  });

  DbAlgorithmPrediction.fromHydrated(DbRatingProject project, PredictionSet predictionSet, AlgorithmPrediction prediction) :
    projectId = project.id,
    predictionSetId = predictionSet.id,
    groupUuid = prediction.shooter.group.uuid,
    scoringGroupUuid = prediction.scoringGroup?.uuid,
    mean = prediction.displayCenter,
    oneSigma = prediction.oneSigma,
    twoSigma = prediction.twoSigma,
    ciOffset = prediction.ciOffset,
    lowPlace = prediction.lowPlace,
    highPlace = prediction.highPlace,
    medianPlace = prediction.medianPlace,
    meanRatio = prediction.expectedRatio,
    oneSigmaRatio = prediction.oneSigmaRatio,
    shiftRatio = prediction.shiftRatio,
    isLogNormal = prediction.isLogNormal,
    logMean = prediction.logMean,
    logSigma = prediction.logSigma {
      this.rating.value = prediction.shooter.wrappedRating;
      this.project.value = project;
      this.group.value = prediction.shooter.group;
      this.scoringGroup.value = prediction.scoringGroup;
      this.predictionSet.value = predictionSet;
      this.memberNumber = prediction.shooter.originalMemberNumber;
    }

  /// Create a list of [DbAlgorithmPrediction] from a list of [AlgorithmPrediction]s, belonging
  /// to [PredictionSet].
  static List<DbAlgorithmPrediction> fromHydratedPredictions(PredictionSet predictionSet, List<AlgorithmPrediction> predictions) {
    var project = predictionSet.matchPrep.value!.ratingProject.value!;
    return predictions.map((p) => DbAlgorithmPrediction.fromHydrated(project, predictionSet, p)).toList();
  }

  AlgorithmPrediction? hydrate({RatingSystem? preloadedAlgorithm, RaterSettings? preloadedSettings, ShooterRating? preloadedRating, bool useRatingCache = false}) {
    preloadedAlgorithm ??= algorithm;
    if(preloadedRating == null) {
      var dbRating = getShooterRatingSync(AnalystDatabase(), useCache: useRatingCache, save: true);
      if(dbRating == null) {
        return null;
      }
      preloadedRating = preloadedAlgorithm.wrapDbRating(dbRating);
    }
    var prediction = AlgorithmPrediction(
      shooter: preloadedRating,
      displayCenter: mean,
      sigma: oneSigma,
      ciOffset: ciOffset,
      settings: preloadedSettings ?? settings,
      algorithm: preloadedAlgorithm,
      expectedRatio: meanRatio,
      oneSigmaRatio: oneSigmaRatio,
      shiftRatio: shiftRatio,
      isLogNormal: isLogNormal,
      logMean: logMean,
      logSigma: logSigma,
      scoringGroup: scoringGroup.value,
    );
    prediction.lowPlace = lowPlace;
    prediction.highPlace = highPlace;
    prediction.medianPlace = medianPlace;
    return prediction;
  }

    Future<AlgorithmPrediction?> hydrateAsync({RatingSystem? preloadedAlgorithm, RaterSettings? preloadedSettings, ShooterRating? preloadedRating, bool useRatingCache = false}) async {
    preloadedAlgorithm ??= algorithm;
    if(preloadedRating == null) {
      var dbRating = await getShooterRating(AnalystDatabase(), useCache: useRatingCache, save: true);
      if(dbRating == null) {
        return null;
      }
      preloadedRating = preloadedAlgorithm.wrapDbRating(dbRating);
    }
    var prediction = AlgorithmPrediction(
      shooter: preloadedRating,
      displayCenter: mean,
      sigma: oneSigma,
      ciOffset: ciOffset,
      settings: preloadedSettings ?? settings,
      algorithm: preloadedAlgorithm,
      expectedRatio: meanRatio,
      oneSigmaRatio: oneSigmaRatio,
      shiftRatio: shiftRatio,
      isLogNormal: isLogNormal,
      logMean: logMean,
      logSigma: logSigma,
      scoringGroup: scoringGroup.value,
    );
    prediction.lowPlace = lowPlace;
    prediction.highPlace = highPlace;
    prediction.medianPlace = medianPlace;
    return prediction;
  }

  /// Convert this [DbAlgorithmPrediction] to a minimal [Shooter] object
  /// that can be used to compare to a [ShootingMatch] entry.
  ///
  /// If [loadFromRating] is true, the shooter's name will be loaded from the
  /// [DbShooterRating] object.
  Shooter asShooter({bool loadFromRating = true}) {
    String firstName = "Unknown";
    String lastName = "Unknown";
    String memberNumber = this.memberNumber;
    //Set<String> knownMemberNumbers = {this.memberNumber};
    if(loadFromRating && rating.value != null) {
      firstName = rating.value!.firstName;
      lastName = rating.value!.lastName;
      memberNumber = rating.value!.memberNumber;
      //knownMemberNumbers = rating.value!.knownMemberNumbers;
    }
    var shooter = Shooter(
      firstName: firstName,
      lastName: lastName,
      memberNumber: memberNumber,
    );
    return shooter;
  }

  Future<void> saveLinks() async {
    await rating.save();
    await project.save();
    await group.save();
    await scoringGroup.save();
    await predictionSet.save();
  }
}
