import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/ui/booth/model.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/filter_dialog.dart';

/// ScorecardSettingsDialog is a modal host for [ScorecardSettings].
class ScorecardSettingsDialog extends StatelessWidget {
  const ScorecardSettingsDialog({super.key, required this.scorecard, required this.match});

  final ScorecardModel scorecard;
  final ShootingMatch match;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Settings"),
      content: ScorecardSettings(scorecard: scorecard, match: match),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text("CANCEL")),
        TextButton(onPressed: () => Navigator.of(context).pop(scorecard), child: const Text("SAVE")),
      ],
    );
  }

  static Future<ScorecardModel?> show(BuildContext context, {required ScorecardModel scorecard, required ShootingMatch match}) {
    return showDialog<ScorecardModel>(
      context: context,
      builder: (context) => ScorecardSettingsDialog(scorecard: scorecard, match: match),
      barrierDismissible: false,
    );
  }
}

/// ScorecardSettings edits the provided scorecard.
/// Edits happen in place, so use [ScorecardModel.copy] to get a copy if confirm/discard is needed.
class ScorecardSettings extends StatefulWidget {
  const ScorecardSettings({super.key, required this.scorecard, required this.match});

  final ScorecardModel scorecard;
  final ShootingMatch match;
  @override
  State<ScorecardSettings> createState() => _ScorecardSettingsState();
}

class _ScorecardSettingsState extends State<ScorecardSettings> {
  late ScorecardModel scorecard;

  TextEditingController nameController = TextEditingController();
  int scoreFilteredCount = 0;
  int displayFilteredCount = 0;
  @override
  void initState() {
    super.initState();
    scorecard = widget.scorecard;
    nameController.text = scorecard.name;
    var scoreFiltered = widget.match.applyFilterSet(scorecard.scoreFilters);
    scoreFilteredCount = scoreFiltered.length;
    
    var displayFiltered = scorecard.displayFilters.apply(widget.match);
    displayFilteredCount = displayFiltered.length;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: nameController,
          decoration: const InputDecoration(labelText: "Name"),
          onChanged: (value) => scorecard.name = value,
        ),
        SizedBox(height: 16),
        Text("Scoring filters match $scoreFilteredCount of ${widget.match.shooters.length} competitors."),
        TextButton(
          child: Text("EDIT SCORING FILTERS"),
          onPressed: () async {
            var filters = await FilterDialog.show(context, scorecard.scoreFilters);
            if(filters != null) {
              scorecard.scoreFilters = filters;
              var scoreFiltered = widget.match.applyFilterSet(scorecard.scoreFilters);
              setState(() {
                scoreFilteredCount = scoreFiltered.length;
              });
            }
          },
        ),
        SizedBox(height: 16),
        Text("Display filters match $displayFilteredCount of ${widget.match.shooters.length} competitors."),
        TextButton(
          child: Text("EDIT DISPLAY FILTERS"),
          onPressed: () async {
            var filters = await FilterDialog.show(context, scorecard.displayFilters.filterSet 
                ?? FilterSet(widget.match.sport, empty: true)
                  ..mode = FilterMode.or
                  ..knownSquads = widget.match.sortedSquadNumbers
            );
            scorecard.displayFilters.filterSet = filters;

            var displayFiltered = scorecard.displayFilters.apply(widget.match);
            setState(() {
              displayFilteredCount = displayFiltered.length;
            });
          },
        ),
      ],
    );
  }
}