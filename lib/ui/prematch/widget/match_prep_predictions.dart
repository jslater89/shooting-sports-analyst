/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shooting_sports_analyst/config/config.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/prediction_set.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/match_prediction.dart';
import 'package:shooting_sports_analyst/ui/prematch/match_prep_model.dart';
import 'package:shooting_sports_analyst/ui/rater/prediction/prediction_view.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/confirm_dialog.dart';
import 'package:shooting_sports_analyst/util.dart';

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
    return ChangeNotifierProvider.value(
      value: localModel,
      child: DefaultTabController(
        length: mainModel.ratingProject.groups.length,
        child: Column(
          children: [
            _PredictionsHeader(),
            Expanded(
              child: _PredictionBody(groups: mainModel.ratingProject.groups),
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

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController();
    model = context.read<_MatchPrepPredictionsModel>();
    model.addListener(updatePredictionSetName);
  }

  @override
  void dispose() {
    model.removeListener(updatePredictionSetName);
    super.dispose();
  }

  void updatePredictionSetName() {
    if(model.selectedPredictionSet == null) {
      nameController.clear();
    }
    else if(nameController.text != model.selectedPredictionSet?.name) {
      nameController.text = model.selectedPredictionSet?.name ?? "";
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
                width: 400.0 * uiScaleFactor,
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
              IconButton(
                icon: Icon(Icons.add),
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
              if(model.selectedPredictionSet != null) IconButton(
                icon: Icon(Icons.delete),
                onPressed: () async {
                  var confirm = await ConfirmDialog.show(context, content: Text("Delete prediction set?"));
                  if(confirm ?? false) {
                    model.deletePredictionSet(model.selectedPredictionSet!);
                  }
                },
              ),
            ],
          ),
        ),
        if(model.selectedPredictionSet != null) TabBar(
          tabs: model.matchPrepModel.ratingProject.groups.map((g) => Tab(text: g.name)).toList(),
        ),
      ]
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

class _PredictionSetTab extends StatelessWidget {
  const _PredictionSetTab({required this.group});
  final RatingGroup group;

  @override
  Widget build(BuildContext context) {
    final outerModel = Provider.of<_MatchPrepPredictionsModel>(context);
    var groupPredictions = outerModel.getPredictionsForGroup(group);
    return ChangeNotifierProvider(
      create: (context) => PredictionViewModel(initialPredictions: groupPredictions),
      child: PredictionListView(),
    );
  }
}


class _MatchPrepPredictionsModel extends ChangeNotifier {
  final MatchPrepPageModel matchPrepModel;

  _MatchPrepPredictionsModel({required this.matchPrepModel});

  List<PredictionSet> get predictionSets => matchPrepModel.prep.predictionSets.toList();
  PredictionSet? selectedPredictionSet;

  Map<RatingGroup, List<AlgorithmPrediction>> _algorithmPredictionCache = {};

  List<AlgorithmPrediction> getPredictionsForGroup(RatingGroup group) {
    if(_algorithmPredictionCache.containsKey(group)) {
      return _algorithmPredictionCache[group]!;
    }
    var predictions = selectedPredictionSet?.algorithmPredictions.where((p) => p.group.value == group).toList();
    _algorithmPredictionCache[group] = predictions?.map((p) => p.hydrate()).nonNulls.toList() ?? [];
    return _algorithmPredictionCache[group]!;
  }

  Future<void> reloadPredictionSets() async {
    await matchPrepModel.prep.predictionSets.load();
    notifyListeners();
  }

  void setSelectedPredictionSet(PredictionSet value) {
    selectedPredictionSet = value;
    _algorithmPredictionCache.clear();
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
    notifyListeners();
  }

  void init() {
    if(predictionSets.isNotEmpty) {
      predictionSets.sort((a, b) => b.created.compareTo(a.created));
      selectedPredictionSet = predictionSets.first;
    }
  }
}