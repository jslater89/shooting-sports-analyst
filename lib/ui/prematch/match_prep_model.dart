import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/extensions/future_match.dart';
import 'package:shooting_sports_analyst/data/database/extensions/match_prep.dart';
import 'package:shooting_sports_analyst/data/database/extensions/registrations.dart';
import 'package:shooting_sports_analyst/data/database/match/rating_project_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/algorithm_prediction.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/match.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/match_prep.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/prediction_set.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/registration.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/registration_mapping.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/match_prediction.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/util.dart';

final _log = SSALogger("MatchPrepPageModel");

/// MatchPrepPageModel is a model for the match prep page, and contains
/// the data and interaction functions for the page and its tabs.
class MatchPrepPageModel extends ChangeNotifier {
  final MatchPrep prep;
  final AnalystDatabase db = AnalystDatabase();

  FutureMatch get futureMatch => prep.futureMatch.value!;
  DbRatingProject get ratingProject => prep.ratingProject.value!;
  Sport get sport => ratingProject.sport;

  List<String> knownSquads = [];
  Map<MatchRegistration, ShooterRating> matchedRegistrations = {};
  Set<ShooterRating> ratingsInUse = {};

  MatchPrepPageModel({required this.prep});

  Future<void> init() async {
    _getKnownSquads(notify: false);
    _loadMatchingRegistrations(notify: false);
  }

  // ===========================
  // Data manipulation functions
  // ===========================

  Future<PredictionSet> createPredictionSet(String name) async {
    // predict for all rating groups
    Map<RatingGroup, List<AlgorithmPrediction>> predictions = {};
    var seed = futureMatch.date.millisecondsSinceEpoch;
    for(var group in ratingProject.groups) {
      var ratings = matchedRegistrations.values.where((r) => r.group == group).toList();
      var groupPredictions = ratingProject.settings.algorithm.predict(ratings, seed: seed);
      predictions[group] = groupPredictions;
    }

    // create and save prediction set
    var predictionSet = PredictionSet.create(
      matchPrep: prep,
      name: name,
    );
    predictionSet = await db.savePredictionSet(predictionSet, savePredictions: false);

    // dehydrate and save algorithm predictions
    List<DbAlgorithmPrediction> dbPredictions = [];
    for(var group in predictions.keys) {
      for(var prediction in predictions[group]!) {
        var dbPrediction = DbAlgorithmPrediction.fromHydrated(ratingProject, predictionSet, prediction);
        dbPredictions.add(dbPrediction);
      }
    }

    List<Future> saveFutures = [];
    for(var prediction in dbPredictions) {
      saveFutures.add(db.saveAlgorithmPrediction(prediction, saveLinks: true));
    }
    await Future.wait(saveFutures);

    // add to prep and save prediction set link, but not the predictions (saved above)
    prep.predictionSets.add(predictionSet);
    await db.saveMatchPrep(prep, savePredictionSetLinks: false);

    notifyListeners();
    return predictionSet;
  }

  Future<void> deletePredictionSet(PredictionSet predictionSet) async {
    prep.predictionSets.remove(predictionSet);
    await db.saveMatchPrep(prep, savePredictionSetLinks: false);
    await db.deletePredictionSet(predictionSet);
    notifyListeners();
  }

  Future<Result<void, MatchPrepModelError>> linkRating(MatchRegistration registration, ShooterRating rating) async {
    var futureMatch = prep.futureMatch.value!;

    // check if there's already a mapping for this registration (either an existing mapping, or a rating in the convenience map)
    var existingMapping = futureMatch.getMappingFor(registration);
    if(existingMapping != null || matchedRegistrations.containsKey(registration)) {
      return Result.err(MatchPrepModelError.registrationAlreadyMapped);
    }

    // verify that the rating is not linked to someone else already
    var otherRegistration = matchedRegistrations.entries.firstWhereOrNull((e) => rating.equalsShooter(e.value) && e.key != registration);
    if(otherRegistration != null) {
      return Result.err(MatchPrepModelError.ratingAlreadyLinked);
    }

    // create and save a registration mapping
    var newMapping = MatchRegistrationMapping(
      matchId: futureMatch.matchId,
      shooterName: registration.shooterName ?? "",
      shooterClassificationName: registration.shooterClassificationName ?? "",
      shooterDivisionName: registration.shooterDivisionName ?? "",
      detectedMemberNumbers: rating.knownMemberNumbers.toList(),
      squad: registration.squad,
    );

    // verify that the mapping is not a duplicate
    existingMapping = futureMatch.mappings.firstWhereOrNull((m) => m == newMapping);
    if(existingMapping != null) {
      return Result.err(MatchPrepModelError.duplicateMapping);
    }

    // Now that we're past all the error conditions, put the target rating in our convenience map
    matchedRegistrations[registration] = rating;
    ratingsInUse.add(rating);

    await db.saveMatchRegistrationMappings(futureMatch.matchId, [newMapping]);

    // add the mapping to the FutureMatch and apply it to the registration immediately
    futureMatch.mappings.add(newMapping);
    await db.saveFutureMatch(futureMatch, updateLinks: [MatchPrepLinkTypes.mappings]);

    registration.shooterMemberNumbers = rating.knownMemberNumbers.toList();
    await db.saveMatchRegistrations([registration]);

    notifyListeners();
    return Result.ok(null);
  }

  /// Fully unlinks a rating from a registration. This will remove both manual and automatic links
  /// (i.e., it will remove any relevant registration mappings and also clear member numbers from the
  /// registration).
  Future<void> unlinkRating(MatchRegistration registration) async {
    var rating = matchedRegistrations[registration];
    if(rating == null) {
      return;
    }
    matchedRegistrations.remove(registration);
    ratingsInUse.remove(rating);
    var existingMapping = futureMatch.getMappingFor(registration);
    if(existingMapping != null) {
      futureMatch.mappings.remove(existingMapping);
      await db.saveMatchRegistrationMappings(futureMatch.matchId, [existingMapping]);
    }

    registration.shooterMemberNumbers = [];
    await db.saveMatchRegistrations([registration]);

    notifyListeners();
  }

  // ===========================
  // Public utility functions
  // ===========================

  int compareRegistrationNames(MatchRegistration a, MatchRegistration b) {
    var aName = a.shooterName;
    var bName = b.shooterName;
    if(aName == null && bName == null) {
      return 0;
    }
    if(aName == null) {
      return 1;
    }
    if(bName == null) {
      return -1;
    }
    aName = aName.split(" ").last;
    bName = bName.split(" ").last;
    var aRating = matchedRegistrations[a];
    var bRating = matchedRegistrations[b];
    if(aRating != null) {
      aName = aRating.lastName;
    }
    if(bRating != null) {
      bName = bRating.lastName;
    }
    return aName.compareTo(bName);
  }

  // ===========================
  // Internal data handling
  // ===========================

  /// Get the known squads for this match, sorted in USPSA-like fashion (by length, then lexically).
  void _getKnownSquads({bool notify = true}) {
    var squadSet = <String>{};
    for(var registration in prep.futureMatch.value!.registrations) {
      if(registration.squad != null) {
        squadSet.add(registration.squad!);
      }
    }
    knownSquads = squadSet.toList();
    knownSquads.sort((a, b) {
      var aLength = a.length;
      var bLength = b.length;
      if(aLength != bLength) {
        return aLength.compareTo(bLength);
      }
      return a.compareTo(b);
    });
    if(notify) {
      notifyListeners();
    }
  }

  // TODO: might be nice to do this on demand in children
  // we'd probably want a debounce timer, so when a few dozen children ask, we get them all
  // at once with a single notifyListeners at the end

  /// Load known registrations for this match into [matchedRegistrations].
  void _loadMatchingRegistrations({bool notify = true}) async {
    var registrations = futureMatch.getRegistrationsFor(sport);
    int matched = 0;
    for(var registration in registrations) {
      if(registration.shooterMemberNumbers.isNotEmpty) {
        var division = sport.divisions.lookupByName(registration.shooterDivisionName);
        if(division == null) {
          continue;
        }
        var ratingGroup = ratingProject.groupForDivisionSync(division);
        if(ratingGroup == null) {
          continue;
        }
        DbShooterRating? rating;
        for(var memberNumber in registration.shooterMemberNumbers) {
          rating = db.maybeKnownShooterSync(project: ratingProject, group: ratingGroup, memberNumber: memberNumber);
          if(rating != null) {
            break;
          }
        }
        if(rating != null) {
          matchedRegistrations[registration] = ratingProject.wrapDbRatingSync(rating);
          ratingsInUse.add(matchedRegistrations[registration]!);
          matched++;
        }
      }
    }
    if(notify) {
      notifyListeners();
    }
    _log.i("Matched ${matched} of ${registrations.length} registrations");
  }

  @override
  void dispose() {
    super.dispose();
  }
}

enum MatchPrepModelError implements ResultErr {
  ratingAlreadyLinked,
  registrationAlreadyMapped,
  duplicateMapping;

  @override
  String get message => switch(this) {
    ratingAlreadyLinked => "Rating is already linked to another registration",
    registrationAlreadyMapped => "Registration is already mapped to a rating",
    duplicateMapping => "Duplicate mapping",
  };
}