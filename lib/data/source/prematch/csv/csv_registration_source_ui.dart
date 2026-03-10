/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/match.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/registration.dart';
import 'package:shooting_sports_analyst/data/source/match_source_error.dart';
import 'package:shooting_sports_analyst/data/source/prematch/csv/csv_registration_source.dart';
import 'package:shooting_sports_analyst/data/source/prematch/registration.dart';
import 'package:shooting_sports_analyst/data/source/prematch/registration_ui.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/future_match_database_chooser_dialog.dart';

class CSVRegistrationSourceUI extends FutureMatchSourceUI {
  @override
  Widget getDownloadMatchUIFor({
    required FutureMatchSource source,
    required void Function(FutureMatch) onMatchSelected,
    void Function(FutureMatch)? onMatchDownloaded,
    required void Function(MatchSourceError) onError,
    String? initialSearch,
  }) {
    source as CSVRegistrationSource;

    FutureMatch? selectedMatch;
    File? selectedCsvFile;
    List<MatchRegistration> registrations = [];
    String? feedback;

    final bool Function() canImport = () {
      if(selectedMatch == null) return false;
      if(selectedCsvFile == null) return false;
      if(registrations.isEmpty) return false;
      return true;
    };

    return StatefulBuilder(
      builder: (context, setState) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 4,
          children: [
            Text("Select a future match, then click the 'import' button to import registrations from a CSV file.\n"
            "This will overwrite all existing registrations for the match.", style: Theme.of(context).textTheme.bodySmall),
            Text("Match", style: Theme.of(context).textTheme.titleMedium),
            Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 8,
              children: [
                Text(selectedMatch?.eventName ?? "(none selected)"),
                TextButton(
                  child: Text("SELECT"),
                  onPressed: () async {
                    var match = await FutureMatchDatabaseChooserDialog.showSingle(context: context);
                    if(match != null) {
                      setState(() {
                        selectedMatch = match;
                      });
                    }
                  },
                )
              ],
            ),
            Text("CSV file", style: Theme.of(context).textTheme.titleMedium),
            Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 8,
              children: [
                Text(selectedCsvFile?.path ?? "(none selected)"),
                TextButton(
                  child: Text("SELECT"),
                  onPressed: selectedMatch == null ? null : () async {
                    var result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ["csv"]);
                    if(result != null) {
                      var processedRegistrations = source.processCsvFile(matchId: selectedMatch!.matchId, csvFile: File(result.files.first.path ?? ""));

                      setState(() {
                        selectedCsvFile = File(result.files.first.path ?? "");
                        registrations = processedRegistrations;
                        feedback = "${processedRegistrations.length} registrations found in file";
                      });
                    }
                  },
                )
              ],
            ),
            if(feedback != null)
              Text(feedback!),
            TextButton(
              child: Text("IMPORT"),
              onPressed: !canImport() ? null : () async {
                await source.importRegistrations(selectedMatch!, registrations);
                setState(() {
                  feedback = "Imported ${registrations.length} registrations into match ${selectedMatch!.matchId}";
                });
              },
            ),
          ],
        );
      }
    );
  }
}