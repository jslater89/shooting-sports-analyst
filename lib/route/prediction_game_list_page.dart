import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shooting_sports_analyst/config/config.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/extensions/prediction_game.dart';
import 'package:shooting_sports_analyst/data/database/schema/prediction_game/prediction_game.dart';
import 'package:shooting_sports_analyst/ui/empty_scaffold.dart';
import 'package:shooting_sports_analyst/ui/prediction_game/prediction_game_list.dart';
import 'package:shooting_sports_analyst/util.dart';

class PredictionGameListPage extends StatefulWidget {
  const PredictionGameListPage({super.key});

  @override
  State<PredictionGameListPage> createState() => _PredictionGameListPageState();
}

class _PredictionGameListPageState extends State<PredictionGameListPage> {
  final model = PredictionGameListModel();

  @override
  void initState() {
    super.initState();
    model.load();
  }

  @override
  Widget build(BuildContext context) {
    return EmptyScaffold(
      title: "Prediction Games",
      actions: [
        IconButton(
          icon: Icon(Icons.add),
          onPressed: () async {
            var predictionGame = await PredictionGameCreationDialog.show(context);
            if(predictionGame != null) {
              await AnalystDatabase().savePredictionGame(predictionGame, saveLinks: true);
              model.load();
            }
          },
        ),
      ],
      child: ChangeNotifierProvider.value(
        value: model,
        child: PredictionGameList(),
      )
    );
  }
}

class PredictionGameCreationDialog extends StatefulWidget {
  const PredictionGameCreationDialog({super.key});

  @override
  State<PredictionGameCreationDialog> createState() => _PredictionGameCreationDialogState();

  static Future<PredictionGame?> show(BuildContext context) async {
    return showDialog<PredictionGame>(
      context: context,
      builder: (context) => PredictionGameCreationDialog(),
      barrierDismissible: false,
    );
  }
}

class _PredictionGameCreationDialogState extends State<PredictionGameCreationDialog> {
  final nameController = TextEditingController();
  final descriptionController = TextEditingController();
  final minimumCompetitorsRequiredController = TextEditingController();
  final startDateController = TextEditingController();
  final endDateController = TextEditingController();
  DateTime? startDate;
  DateTime? endDate;

  String errorMessage = "";

  @override
  Widget build(BuildContext context) {
    final uiScaleFactor = ChangeNotifierConfigLoader().uiConfig.uiScaleFactor;
    return AlertDialog(
      title: Text("Create Prediction Game"),
      content: SizedBox(
        width: 500 * uiScaleFactor,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 10,
          children: [
            TextFormField(
              controller: nameController,
              decoration: InputDecoration(labelText: "Name"),
            ),
            TextFormField(
              controller: descriptionController,
              decoration: InputDecoration(labelText: "Description"),
              maxLines: 3,
            ),
            Row(
              spacing: 5 * uiScaleFactor,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: minimumCompetitorsRequiredController,
                    decoration: InputDecoration(labelText: "Min. competitors"),
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: startDateController,
                    decoration: InputDecoration(
                      labelText: "Start date",
                      suffixIcon: IconButton(
                        icon: Icon(Icons.calendar_month),
                        onPressed: () async {
                          var date = await showDatePicker(
                            context: context,
                            initialDate: startDate ?? DateTime.now(),
                            firstDate: practicalShootingZeroDate,
                            lastDate: DateTime.now(),
                          );
                          if(date != null) {
                            setState(() {
                              startDate = date;
                            });
                            startDateController.text = programmerYmdFormat.format(date);
                          }
                        },
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: endDateController,
                    decoration: InputDecoration(
                      labelText: "End date",
                      suffixIcon: IconButton(
                        icon: Icon(Icons.calendar_month),
                        onPressed: () async {
                          var date = await showDatePicker(
                            context: context,
                            initialDate: endDate ?? DateTime.now(),
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(Duration(days: 365 * 5)),
                          );
                          if(date != null) {
                            setState(() {
                              endDate = date;
                            });
                            endDateController.text = programmerYmdFormat.format(date);
                          }
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if(errorMessage.isNotEmpty)
              Text(errorMessage)
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text("CANCEL")),
        TextButton(
          child: Text("CREATE"),
          onPressed: () {
            var name = nameController.text.trim();
            var description = descriptionController.text.trim();
            var minimumCompetitorsRequired = int.tryParse(minimumCompetitorsRequiredController.text.trim());
            if(name.isEmpty) {
              setState(() {
                errorMessage = "Name is required";
              });
              return;
            }
            if(minimumCompetitorsRequired == null) {
              setState(() {
                errorMessage = "Minimum competitors is required";
              });
              return;
            }

            var predictionGame = PredictionGame(
              name: name,
              description: description,
              minimumCompetitorsRequired: minimumCompetitorsRequired,
              created: DateTime.now(),
              start: startDate,
              end: endDate,
            );
            Navigator.of(context).pop(predictionGame);
          }
        ),
      ],
    );
  }
}