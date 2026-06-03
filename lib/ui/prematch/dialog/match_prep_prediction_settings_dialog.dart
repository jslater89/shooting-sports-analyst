/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/extensions/match_prep.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/match_prep.dart';
import 'package:shooting_sports_analyst/data/match_prep/match_prep_uspsa_prediction_settings.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';

/// Prediction settings for a match prep. Currently supports USPSA LO/CO options only.
class MatchPrepPredictionSettingsDialog extends StatefulWidget {
  const MatchPrepPredictionSettingsDialog({
    super.key,
    required this.prep,
    required this.sport,
  });

  final MatchPrep prep;
  final Sport sport;

  static Future<bool> show(BuildContext context, {
    required MatchPrep prep,
    required Sport sport,
  }) async {
    if(!MatchPrepUspsaPredictionSettings.isSupportedSport(sport)) {
      return false;
    }
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => MatchPrepPredictionSettingsDialog(prep: prep, sport: sport),
    );
    return saved ?? false;
  }

  @override
  State<MatchPrepPredictionSettingsDialog> createState() => _MatchPrepPredictionSettingsDialogState();
}

class _MatchPrepPredictionSettingsDialogState extends State<MatchPrepPredictionSettingsDialog> {
  late bool combineLoCo;
  late bool generateLoCoPredictions;

  @override
  void initState() {
    super.initState();
    combineLoCo = MatchPrepUspsaPredictionSettings.combinesLoCo(widget.prep);
    generateLoCoPredictions = MatchPrepUspsaPredictionSettings.generatesLoCoPredictions(widget.prep);
  }

  Future<void> _save() async {
    MatchPrepUspsaPredictionSettings.applyTo(
      widget.prep,
      combineLoCo: combineLoCo,
      generateLoCoPredictions: generateLoCoPredictions,
    );
    await AnalystDatabase().saveMatchPrep(widget.prep);
    if(mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("Prediction settings"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: Text("Combine LO/CO for LO and CO predictions"),
            subtitle: Text("Use combined LO/CO ratings when predicting Limited Optics and Carry Optics finishes"),
            value: combineLoCo,
            onChanged: (value) {
              setState(() {
                combineLoCo = value ?? false;
              });
            },
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: Text("Generate LO/CO predictions"),
            subtitle: Text("Include a combined Limited Optics / Carry Optics prediction group"),
            value: generateLoCoPredictions,
            onChanged: (value) {
              setState(() {
                generateLoCoPredictions = value ?? false;
              });
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text("CANCEL"),
        ),
        TextButton(
          onPressed: _save,
          child: Text("SAVE"),
        ),
      ],
    );
  }
}
