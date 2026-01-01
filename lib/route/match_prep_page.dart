/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/extensions/match_prep.dart';
import 'package:shooting_sports_analyst/data/database/match/rating_project_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/algorithm_prediction.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/match.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/match_prep.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/prediction_set.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/registration.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/match_prediction.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/ui/empty_scaffold.dart';
import 'package:shooting_sports_analyst/ui/prematch/widget/match_prep_divisions.dart';
import 'package:shooting_sports_analyst/ui/prematch/widget/match_prep_predictions.dart';
import 'package:shooting_sports_analyst/ui/prematch/widget/match_prep_squadding.dart';

final _log = SSALogger("MatchPrepPage");

/// A match prep page displays details of a match prep. It has controls for showing
/// predictions, ratings, a breakdown of registrations, the registration mapping dialog,
/// and other items of interest.
class MatchPrepPage extends StatefulWidget {
  const MatchPrepPage({super.key, required this.prep});

  final MatchPrep prep;

  @override
  State<MatchPrepPage> createState() => _MatchPrepPageState();
}

class _MatchPrepPageState extends State<MatchPrepPage> with TickerProviderStateMixin {

  late MatchPrepPageModel _model;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _model = MatchPrepPageModel(prep: widget.prep);
    _model.init();
    _tabController = TabController(length: _MatchPrepPageTab.values.length, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _model,
      child: EmptyScaffold(
        title: _model.futureMatch.eventName,
        child: Column(
          children: [
            TabBar(
              controller: _tabController,
              tabs: _MatchPrepPageTab.values.map((tab) => Tab(text: tab.uiLabel)).toList(),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  ..._MatchPrepPageTab.values.map((tab) => tab.build(context, _model)).toList(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _MatchPrepPageTab {
  squadding,
  divisions,
  predictions;

  String get uiLabel =>
    switch(this) {
      _MatchPrepPageTab.squadding => "Squadding",
      _MatchPrepPageTab.divisions => "Divisions",
      _MatchPrepPageTab.predictions => "Predictions",
    };

  Widget build(BuildContext context, MatchPrepPageModel model) =>
    switch(this) {
      _MatchPrepPageTab.squadding =>
        MatchPrepSquadding(),
      _MatchPrepPageTab.divisions =>
        MatchPrepDivisions(groups: model.ratingProject.groups),
      _MatchPrepPageTab.predictions =>
        MatchPrepPredictions(),
    };
}

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

  // ===========================
  // Public utility functions
  // ===========================

  int compareRegistrations(MatchRegistration a, MatchRegistration b) {
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