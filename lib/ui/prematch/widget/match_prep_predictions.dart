/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:archive/archive.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shooting_sports_analyst/config/config.dart';
import 'package:shooting_sports_analyst/data/database/match/hydrated_cache.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/prediction_set.dart';
import 'package:shooting_sports_analyst/data/math/ratio_forecast_stats.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_system.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/match_prediction.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/filter_set.dart';
import 'package:shooting_sports_analyst/html_or/html_or.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/ui/prematch/dialog/match_prep_prediction_settings_dialog.dart';
import 'package:shooting_sports_analyst/ui/prematch/match_prep_model.dart';
import 'package:shooting_sports_analyst/ui/rater/prediction/prediction_view.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/confirm_dialog.dart';
import 'package:shooting_sports_analyst/util.dart';

final _log = SSALogger("MatchPrepPredictions");

/// The predictions tab displays prediction sets from the match prep.
class MatchPrepPredictions extends StatefulWidget {
  // This tab does three things:
  // 1. Displays a list of prediction sets for the match prep. (Dropdown by date?)
  // 2. Displays a tab bar with the names of all rating groups in the project.
  // 3. Displays the predictions for a given prediction set and rating group.
  const MatchPrepPredictions({super.key});

  @override
  State<MatchPrepPredictions> createState() => _MatchPrepPredictionsState();
}

class _MatchPrepPredictionsState extends State<MatchPrepPredictions> with AutomaticKeepAliveClientMixin{
  late MatchPrepPageModel mainModel;
  late _MatchPrepPredictionsModel localModel;

  @override
  void initState() {
    super.initState();

    mainModel = context.read<MatchPrepPageModel>();
    localModel = _MatchPrepPredictionsModel(matchPrepModel: mainModel);
    localModel.init();
    mainModel.addListener(localModel.reloadPredictionSets);
  }

  @override
  void dispose() {
    mainModel.removeListener(localModel.reloadPredictionSets);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // rebuild on main model changes
    var mainModel = Provider.of<MatchPrepPageModel>(context);
    final groups = mainModel.getNonexcludedRatingGroups();
    return ChangeNotifierProvider.value(
      value: localModel,
      child: DefaultTabController(
        key: ValueKey(groups.map((g) => g.uuid).join(",")),
        length: groups.length,
        child: Column(
          children: [
            _PredictionsHeader(),
            Expanded(
              child: _PredictionBody(groups: groups),
            )
          ]
        ),
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;
}

class _PredictionsHeader extends StatefulWidget {
  @override
  State<_PredictionsHeader> createState() => _PredictionsHeaderState();
}

class _PredictionsHeaderState extends State<_PredictionsHeader> {
  late TextEditingController nameController;
  late _MatchPrepPredictionsModel model;

  Map<RatingGroup, List<AlgorithmPrediction>> predictions = {};

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController();
    model = context.read<_MatchPrepPredictionsModel>();
    model.addListener(updatePredictionSet);
  }

  @override
  void dispose() {
    model.removeListener(updatePredictionSet);
    super.dispose();
  }

  void updatePredictionSet() {
    if(model.selectedPredictionSet == null) {
      nameController.clear();
    }
    else if(nameController.text != model.selectedPredictionSet?.name) {
      nameController.text = model.selectedPredictionSet?.name ?? "";

      for(var group in model.matchPrepModel.getNonexcludedRatingGroups()) {
        predictions[group] = model.getPredictionsForGroup(group);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final uiScaleFactor = ChangeNotifierConfigLoader().uiConfig.uiScaleFactor;
    var model = Provider.of<_MatchPrepPredictionsModel>(context);
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.all(12.0 * uiScaleFactor),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 8 * uiScaleFactor,
            children: [
              DropdownMenu<PredictionSet>(
                width: 250.0 * uiScaleFactor,
                label: Text("Prediction set"),
                initialSelection: model.selectedPredictionSet,
                controller: nameController,
                onSelected: (value) {
                  if(value != null) {
                    model.setSelectedPredictionSet(value);
                  }
                },
                dropdownMenuEntries: model.predictionSets.map((e) => DropdownMenuEntry(value: e, label: e.name)).toList(),
              ),
              TextButton(
                child: Row(
                  children: [
                    Icon(Icons.add),
                    Text("CREATE"),
                  ],
                ),
                onPressed: () async {
                  final defaultName = programmerYmdHmFormat.format(DateTime.now());
                  final nameController = TextEditingController(text: defaultName);
                  var predictionSetName = await showDialog<String>(context: context, builder: (context) {
                    return AlertDialog(
                      title: Text("Create prediction set"),
                      content: TextField(
                        controller: nameController,
                        decoration: InputDecoration(
                          hintText: "Prediction set name",
                        ),
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text("CANCEL")),
                        TextButton(
                          onPressed: nameController.text.isEmpty ? null : () => Navigator.of(context).pop(nameController.text),
                          child: Text("CREATE"),
                        ),
                      ],
                    );
                  });

                  if(predictionSetName != null) {
                    model.createPredictionSet(predictionSetName);
                  }
                },
              ),
              if(model.selectedPredictionSet != null) TextButton(
                child: Row(
                  children: [
                    Icon(Icons.delete),
                    Text("DELETE"),
                  ],
                ),
                onPressed: () async {
                  var confirm = await ConfirmDialog.show(context, content: Text("Delete prediction set?"));
                  if(confirm ?? false) {
                    model.deletePredictionSet(model.selectedPredictionSet!);
                  }
                },
              ),
              TextButton(
                child: Row(
                  children: [
                    Icon(Icons.download),
                    Text("EXPORT"),
                  ],
                ),
                onPressed: () async {
                  model.exportPredictionsCsv();
                },
              ),
              if(MatchPrepUspsaPredictionSettings.isSupportedSport(model.matchPrepModel.sport)) TextButton(
                child: Row(
                  children: [
                    Icon(Icons.settings),
                    Text("SETTINGS"),
                  ],
                ),
                onPressed: () async {
                  final saved = await MatchPrepPredictionSettingsDialog.show(
                    context,
                    prep: model.matchPrepModel.prep,
                    sport: model.matchPrepModel.sport,
                  );
                  if(saved) {
                    model.matchPrepModel.notifyPredictionSettingsChanged();
                    model.reloadPredictionSets();
                  }
                },
              ),
            ],
          ),
        ),
        if(model.selectedPredictionSet != null) TabBar(
          tabs: model.matchPrepModel.getNonexcludedRatingGroups().map((g) => Tab(text: g.uiLabel)).toList(),
        ),
      ],
    );
  }
}

class _PredictionBody extends StatelessWidget {
  const _PredictionBody({required this.groups});
  final List<RatingGroup> groups;

  @override
  Widget build(BuildContext context) {
    var model = Provider.of<_MatchPrepPredictionsModel>(context);
    if(model.selectedPredictionSet == null) {
      return Center(child: Text("No prediction set selected"));
    }
    else {
      return TabBarView(children: groups.map((g) => _PredictionSetTab(group: g)).toList());
    }
  }
}

class _PredictionSetTab extends StatefulWidget {
  const _PredictionSetTab({required this.group});
  final RatingGroup group;

  @override
  State<_PredictionSetTab> createState() => _PredictionSetTabState();
}

class _PredictionSetTabState extends State<_PredictionSetTab> {
  late PredictionViewModel model;
  late int lastPredictionSetId;
  late String lastRatingGroupUuid;
  late bool lastHadOutcomes;

  @override
  void initState() {
    super.initState();
    final outerModel = Provider.of<_MatchPrepPredictionsModel>(context, listen: false);
    lastPredictionSetId = outerModel.selectedPredictionSet?.id ?? 0;
    lastRatingGroupUuid = widget.group.uuid;
    model = outerModel.tabModels[widget.group]!;
    _updateOutcomes(outerModel);
    lastHadOutcomes = outerModel.matchPrepModel.futureMatch.sourceCode != null;
  }

  Future<void> _updateOutcomes(_MatchPrepPredictionsModel outerModel) async {
    if(outerModel.matchPrepModel.futureMatch.dbMatch.value != null) {
      var matchRes = HydratedMatchCache().get(outerModel.matchPrepModel.futureMatch.dbMatch.value!);
      if(matchRes.isOk()) {
        Map<AlgorithmPrediction, SimpleMatchResult> outcomes = {};
        var match = matchRes.unwrap();
        var filters = widget.group.filters;
        var shooters = match.filterShooters(
          filterMode: FilterMode.and,
          divisions: filters.activeDivisions.toList(),
          allowReentries: false,
        );
        var scores = match.getScores(
          shooters: shooters,
          scoreDQ: false,
        );
        for(var prediction in model.predictions) {
          var score = scores.entries
            .firstWhereOrNull((element) => element.key.equalsShooter(prediction.shooter))?.value;
          if(score != null) {
            outcomes[prediction] = SimpleMatchResult(raterScore: prediction.displayCenter, percent: score.ratio, place: score.place);
          }
        }
        lastHadOutcomes = true;
        model.setOutcomes(outcomes);
        if (kDebugMode && outcomes.isNotEmpty) {
          final stats = RatioForecastStatsAccumulator();
          for (final entry in outcomes.entries) {
            stats.tryAddPrediction(
              entry.key,
              actualRatio: entry.value.percent,
              actualPlace: entry.value.place,
            );
          }
          if (stats.n > 0) {
            _log.d(
              stats.debugSummary(
                prefix:
                    "Prediction vs outcome [${widget.group.uiLabel}]: ",
              ),
            );
          }
        }
      }
      else {
        lastHadOutcomes = false;
        model.setOutcomes({});
      }
    }
    else {
      lastHadOutcomes = false;
      model.setOutcomes({});
    }
  }

  void updatePredictionViewModel(_MatchPrepPredictionsModel outerModel) {
    if(outerModel.selectedPredictionSet?.id != lastPredictionSetId || widget.group.uuid != lastRatingGroupUuid) {
      lastPredictionSetId = outerModel.selectedPredictionSet?.id ?? 0;
      lastRatingGroupUuid = widget.group.uuid;
      var groupPredictions = outerModel.getPredictionsForGroup(widget.group);
      model.setPredictions(groupPredictions, notify: false);
    }

    bool outerModelHasOutcomes = outerModel.matchPrepModel.futureMatch.sourceCode != null;
    if(outerModelHasOutcomes != lastHadOutcomes) {
      _updateOutcomes(outerModel);
    }
  }

  @override
  Widget build(BuildContext context) {
    var outerModel = Provider.of<_MatchPrepPredictionsModel>(context);
    updatePredictionViewModel(outerModel);
    return ChangeNotifierProvider.value(
      value: model,
      child: PredictionListView(),
    );
  }
}


class _MatchPrepPredictionsModel extends ChangeNotifier {
  final MatchPrepPageModel matchPrepModel;

  Map<RatingGroup, PredictionViewModel> tabModels = {};

  _MatchPrepPredictionsModel({required this.matchPrepModel});

  List<PredictionSet> get predictionSets => matchPrepModel.prep.sortedPredictionSets;
  PredictionSet? selectedPredictionSet;

  Map<RatingGroup, List<AlgorithmPrediction>> _algorithmPredictionCache = {};

  List<AlgorithmPrediction> getPredictionsForGroup(RatingGroup group) {
    if(_algorithmPredictionCache.containsKey(group)) {
      return _algorithmPredictionCache[group]!;
    }

    var predictions = selectedPredictionSet?.algorithmPredictions.where((p) => p.effectiveScoringGroup == group).toList();
    _algorithmPredictionCache[group] = predictions?.map((p) => p.hydrate()).nonNulls.toList() ?? [];
    return _algorithmPredictionCache[group]!;
  }

  Future<void> reloadPredictionSets() async {
    await matchPrepModel.prep.predictionSets.load();
    _initTabModels();
    notifyListeners();
  }

  void setSelectedPredictionSet(PredictionSet value) {
    selectedPredictionSet = value;
    _algorithmPredictionCache.clear();
    _initTabModels();
    notifyListeners();
  }

  Future<void> createPredictionSet(String name) async {
    var predictionSet = await matchPrepModel.createPredictionSet(name);
    setSelectedPredictionSet(predictionSet);
  }

  Future<void> deletePredictionSet(PredictionSet predictionSet) async {
    await matchPrepModel.deletePredictionSet(predictionSet);
    if(selectedPredictionSet == predictionSet) {
      selectedPredictionSet = null;
      _algorithmPredictionCache.clear();
    }
    _initTabModels();
    notifyListeners();
  }

  void init() {
    if(predictionSets.isNotEmpty) {
      predictionSets.sort((a, b) => b.created.compareTo(a.created));
      selectedPredictionSet = predictionSets.first;
    }

    _initTabModels();
  }

  void _initTabModels() {
    tabModels = {};
    for(var group in matchPrepModel.getNonexcludedRatingGroups()) {
      var groupPredictions = getPredictionsForGroup(group);
      tabModels[group] = PredictionViewModel(
        dataSource: matchPrepModel.ratingProject,
        matchId: matchPrepModel.futureMatch.matchId,
        initialPredictions: groupPredictions,
        showWager: true,
        showExport: false,
      );
    }
  }

  void exportPredictionsCsv() {
    // A map of rating group name to csv file contents.
    Map<String, String> csvFiles = {};

    for(var group in tabModels.keys) {
      var csv = tabModels[group]!.exportPredictionsCsv();
      csvFiles[group.name] = csv;
    }

    // Create a zip file with the csv file contents.
    final archive = Archive();
    for(var entry in csvFiles.entries) {
      archive.add(ArchiveFile.string(entry.key + ".csv", entry.value));
    }
    var zip = ZipEncoder().encode(archive, autoClose: true);
    HtmlOr.saveBuffer("predictions.zip", zip);
  }
}