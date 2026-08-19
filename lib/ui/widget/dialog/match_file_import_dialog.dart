/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "dart:convert";
import "dart:io";

import "package:archive/archive.dart";
import "package:file_picker/file_picker.dart";
import "package:flutter/material.dart";
import "package:shooting_sports_analyst/api/miff/impl/miff_importer.dart";
import "package:shooting_sports_analyst/api/riff/impl/riff_importer.dart";
import "package:shooting_sports_analyst/closed_sources/psv2/psv2_source.dart";
import "package:shooting_sports_analyst/config/config.dart";
import "package:shooting_sports_analyst/data/database/analyst_database.dart";
import "package:shooting_sports_analyst/data/database/extensions/future_match.dart";
import "package:shooting_sports_analyst/data/database/schema/match_prep/match.dart";
import "package:shooting_sports_analyst/data/import/type_detector.dart";
import "package:shooting_sports_analyst/data/source/auto_importer.dart";
import "package:shooting_sports_analyst/data/source/practiscore_report.dart";
import "package:shooting_sports_analyst/data/source/psc/matchdef/match_info_zip.dart";
import "package:shooting_sports_analyst/data/sport/builtins/registry.dart";
import "package:shooting_sports_analyst/data/sport/builtins/uspsa.dart";
import "package:shooting_sports_analyst/data/sport/match/match.dart";
import "package:shooting_sports_analyst/data/sport/sport.dart";
import "package:shooting_sports_analyst/logger.dart";
import "package:shooting_sports_analyst/ui/rater/prediction/registration_parser.dart";
import "package:shooting_sports_analyst/ui/result_page.dart";
import "package:shooting_sports_analyst/util.dart";

final _log = SSALogger("MatchFileImportDialog");

/// Whether the format can be opened in a results-style viewer once data exists.
/// TODO: Expand when more viewers exist; may also depend on parsed type when [MatchImportFormat.autoDetect] is used.
bool matchImportFormatIsViewable(FileImportFormat format) {
  return format == FileImportFormat.practiscoreReportTxt || format == FileImportFormat.practiscorePsc || format == FileImportFormat.miff;
}

class MatchFileImportDialog extends StatefulWidget {
  const MatchFileImportDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (context) => const MatchFileImportDialog(),
    );
  }

  @override
  State<MatchFileImportDialog> createState() => _MatchFileImportDialogState();
}

class _MatchFileImportDialogState extends State<MatchFileImportDialog> {
  PlatformFile? _pickedFile;
  FileImportFormat _format = FileImportFormat.autoDetect;
  final List<String> _feedbackLines = [];
  final TextEditingController _dateController = TextEditingController();

  /// True once the import process has completed successfully; replaces
  /// the 'import' button with a 'reset' button.
  bool _imported = false;
  ShootingMatch? _processedMatch;
  FutureMatch? _processedFutureMatch;

  String? _pendingRegistrationHtml;
  Sport? _selectedSport;
  DateTime? _selectedDate;

  bool get _hasProcessedData => _processedMatch != null || _processedFutureMatch != null;

  bool get _awaitingRegistrationMetadata =>
      _pendingRegistrationHtml != null && !_hasProcessedData;

  String get _fileDisplayLabel {
    final f = _pickedFile;
    if (f == null) {
      return "No file selected";
    }
    return f.path?.isNotEmpty == true ? f.path! : f.name;
  }

  @override
  void dispose() {
    _dateController.dispose();
    super.dispose();
  }

  void _clearRegistrationPendingState() {
    _pendingRegistrationHtml = null;
    _selectedSport = null;
    _selectedDate = null;
    _dateController.clear();
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.pickFiles(dialogTitle: "Select a file", withData: false);
      if (!mounted) {
        return;
      }
      if (result == null || result.files.isEmpty) {
        return;
      }
      final file = File(result.files.first.path ?? "");
      final format = await detectFormat(file);
      if (format == null) {
        setState(() {
          var feedback = "Failed to detect file format";
          if(_pickedFile != null) {
            feedback += " (leaving existing file in place)";
          }
          _feedbackLines.add(feedback);
        });
        return;
      }
      setState(() {
        _pickedFile = result.files.first;
        _format = format;
        _imported = false;
        _processedMatch = null;
        _processedFutureMatch = null;
        _clearRegistrationPendingState();
        _feedbackLines
          ..clear()
          ..add("File format detected: ${format.label}");
      });

      await _processFile(file, format);
    } catch (e, st) {
      _log.e("File pick failed", error: e, stackTrace: st);
      if (mounted) {
        setState(() {
          _clearRegistrationPendingState();
          _feedbackLines.add("Failed to pick file: $e");
        });
      }
    }
  }

  Future<void> _handleRegistrationImport(String registrationHtml) async {
    final metadata = extractRegistrationHtmlMetadata(registrationHtml);

    setState(() {
      _pendingRegistrationHtml = registrationHtml;
      if(metadata.matchName != null) {
        _feedbackLines.add("Match: ${metadata.matchName}");
      }
      if(metadata.matchId != null) {
        _feedbackLines.add("Match ID: ${metadata.matchId}");
      }
    });

    Sport? sport;
    if(metadata.sportName != null && metadata.sportName != "unknown") {
      sport = SportRegistry().lookup(metadata.sportName!, caseSensitive: false);
    }

    if(sport != null && metadata.date != null) {
      setState(() {
        _selectedSport = sport;
        _selectedDate = metadata.date;
        _dateController.text = programmerYmdFormat.format(metadata.date!);
      });
      await _processRegistrationHtml();
      return;
    }

    setState(() {
      _selectedSport = sport;
      _selectedDate = metadata.date;
      _dateController.text = metadata.date != null ? programmerYmdFormat.format(metadata.date!) : "";
      _feedbackLines.add("Select sport and date to continue");
    });
  }

  Future<void> _processRegistrationHtml() async {
    final sport = _selectedSport;
    final date = _selectedDate;
    final html = _pendingRegistrationHtml;
    if(sport == null || date == null || html == null) {
      return;
    }

    var result = await AutoImporter.getFutureMatchFromHtml(
      html,
      sportOverride: sport,
      dateOverride: date,
    );
    if(!mounted) {
      return;
    }
    if(result.isErr()) {
      setState(() {
        _feedbackLines.add("Failed to process match: ${result.unwrapErr().message}");
      });
      return;
    }
    final (futureMatch, registrations) = result.unwrap();
    setState(() {
      _processedFutureMatch = futureMatch;
      _processedFutureMatch!.newRegistrations = registrations;
      _feedbackLines.add("Match processed successfully (${_processedFutureMatch!.newRegistrations.length} registrations)");
    });
  }

  void _onSportSelected(String? sportName) {
    if(sportName == null) {
      return;
    }
    setState(() {
      _selectedSport = SportRegistry().lookup(sportName, caseSensitive: false);
    });
    _processRegistrationHtml();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: practicalShootingZeroDate,
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if(picked == null || !mounted) {
      return;
    }
    setState(() {
      _selectedDate = picked;
      _dateController.text = programmerYmdFormat.format(picked);
    });
    await _processRegistrationHtml();
  }

  void _onDateSubmitted(String text) {
    if(text.isEmpty) {
      setState(() {
        _selectedDate = null;
      });
      return;
    }
    try {
      final date = programmerYmdFormat.parseLoose(text);
      setState(() {
        _selectedDate = date;
        _dateController.text = programmerYmdFormat.format(date);
      });
      _processRegistrationHtml();
    }
    on FormatException catch (e) {
      _log.w("Format error", error: e);
    }
  }

  Future<void> _processFile(File file, FileImportFormat format) async {
    switch(format) {
      case FileImportFormat.practiscoreReportTxt:
        final source = PractiscoreHitFactorReportParser(uspsaSport);
        final result = await source.parseWebReport(file.readAsStringSync());
        if(result.isErr()) {
          setState(() {
            _feedbackLines.add("Failed to process match: ${result.unwrapErr().message}");
          });
          return;
        }
        setState(() {
          _processedMatch = result.unwrap();
          _feedbackLines.add("Match processed successfully (${_processedMatch!.shooters.length} shooters)");
        });
      case FileImportFormat.practiscorePsc:
        var source = PSv2MatchSource();
        final matchInfoFiles = await MatchInfoFiles.unzipMatchInfoZip(file.readAsBytesSync(), useUtf8: true);
        final result = await source.getMatchFromInfoFiles(matchInfoFiles.unwrap());
        if(result.isErr()) {
          setState(() {
            _feedbackLines.add("Failed to process match: ${result.unwrapErr().message}");
          });
          return;
        }
        setState(() {
          _processedMatch = result.unwrap();
          _feedbackLines.add("Match processed successfully (${_processedMatch!.shooters.length} shooters)");
        });
      case FileImportFormat.miff:
        var importer = MiffImporter();
        final result = importer.importMatch(file.readAsBytesSync());
        if(result.isErr()) {
          setState(() {
            _feedbackLines.add("Failed to process match: ${result.unwrapErr().message}");
          });
          return;
        }
        setState(() {
          _processedMatch = result.unwrap();
          _feedbackLines.add("Match processed successfully (${_processedMatch!.shooters.length} shooters)");
        });
      case FileImportFormat.riff:
        var importer = RiffImporter();
        final result = importer.importMatch(file.readAsBytesSync());
        if(result.isErr()) {
          setState(() {
            _feedbackLines.add("Failed to process match: ${result.unwrapErr().message}");
          });
          return;
        }
        setState(() {
          _processedFutureMatch = result.unwrap();
          _feedbackLines.add("Match processed successfully (${_processedFutureMatch!.newRegistrations.length} registrations)");
        });
      case FileImportFormat.practiscoreRegistrationZip:
        final zipFile = ZipDecoder().decodeBytes(file.readAsBytesSync());
        final archiveFile = zipFile.files.firstWhere((entry) => entry.name == "squadding.html");
        final registrationHtml = utf8.decode(archiveFile.content);
        await _handleRegistrationImport(registrationHtml);
      case FileImportFormat.practiscoreRegistrationHtml:
        final registrationHtml = file.readAsStringSync();
        await _handleRegistrationImport(registrationHtml);
      default:
        _log.w("Unhandled file format: $format");
    }
  }

  void _onCancel() {
    Navigator.of(context).pop();
  }

  Future<void> onReset() async {
    setState(() {
      _pickedFile = null;
      _format = FileImportFormat.autoDetect;
      _imported = false;
      _processedMatch = null;
      _processedFutureMatch = null;
      _clearRegistrationPendingState();
      _feedbackLines.clear();
    });
  }

  Future<void> onImport() async {
    if(_processedMatch != null) {
      var result = await AnalystDatabase().saveMatch(_processedMatch!);
      if(result.isErr()) {
        setState(() {
          _feedbackLines.add("Failed to import match: ${result.unwrapErr().message}");
        });
        return;
      }
      setState(() {
      _feedbackLines.add("Imported match successfully");
      });
    }
    else if(_processedFutureMatch != null) {
      var newRegistrations = _processedFutureMatch!.newRegistrations;
      _processedFutureMatch!.newRegistrations = [];
      var result = await AnalystDatabase().saveFutureMatch(_processedFutureMatch!, newRegistrations: newRegistrations);
      if(result.isErr()) {
        setState(() {
          _feedbackLines.add("Failed to import match: ${result.unwrapErr().message}");
        });
        return;
      }
      setState(() {
        _feedbackLines.add("Imported match successfully");
      });
    }
    else {
      _log.w("Nothing to import");
    }
    setState(() {
      _imported = true;
    });
  }

  Future<void> onView() async {
    if (_processedMatch != null) {
      return Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (context) => ResultPage(canonicalMatch: _processedMatch!),
        ),
      );
    }
  }

  void _onDateChanged(String text) {
    if(text.isEmpty) {
      setState(() {
        _selectedDate = null;
      });
    }
    else {
      final date = programmerYmdFormat.tryParseLoose(text);
      if(date != null) {
        setState(() {
          _selectedDate = date;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scale = ChangeNotifierConfigLoader().uiConfig.uiScaleFactor;
    final importEnabled = _hasProcessedData;
    final viewEnabled = _hasProcessedData && (_processedMatch != null);

    VoidCallback? importResetHandler;
    if(importEnabled) {
      if(!_imported) {
        importResetHandler = onImport;
      }
      else {
        importResetHandler = onReset;
      }
    }
    else {
      importResetHandler = null;
    }

    return AlertDialog(
      title: const Text("Import Match File"),
      content: SizedBox(
        width: 520 * scale,
        height: 480 * scale,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                FilledButton.tonalIcon(
                  onPressed: _pickFile,
                  icon: const Icon(Icons.folder_open),
                  label: const Text("Choose File"),
                ),
                SizedBox(width: 12 * scale),
                Expanded(
                  child: Text(
                    _fileDisplayLabel,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
            SizedBox(height: 16 * scale),
            InputDecorator(
              decoration: const InputDecoration(
                labelText: "File Type",
                border: OutlineInputBorder(),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<FileImportFormat>(
                  isExpanded: true,
                  value: _format,
                  items: FileImportFormat.values
                      .map(
                        (e) => DropdownMenuItem<FileImportFormat>(
                          value: e,
                          child: Text(e.label),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) {
                      setState(() => _format = v);
                    }
                  },
                ),
              ),
            ),
            if(_awaitingRegistrationMetadata) ...[
              SizedBox(height: 12 * scale),
              Row(
                children: [
                  Expanded(
                    child: DropdownMenu<String>(
                      label: const Text("Sport"),
                      initialSelection: _selectedSport?.name,
                      dropdownMenuEntries: SportRegistry().availableSports
                          .map((s) => DropdownMenuEntry(value: s.name, label: s.name))
                          .toList(),
                      onSelected: _onSportSelected,
                    ),
                  ),
                  SizedBox(width: 12 * scale),
                  Expanded(
                    child: TextField(
                      decoration: InputDecoration(
                        labelText: "Date",
                        floatingLabelBehavior: FloatingLabelBehavior.always,
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if(_selectedDate != null)
                              Icon(Icons.check),
                            IconButton(
                              icon: const Icon(Icons.calendar_month),
                              onPressed: _pickDate,
                            ),
                          ],
                        ),
                      ),
                      controller: _dateController,
                      onSubmitted: _onDateSubmitted,
                      onChanged: _onDateChanged,
                    ),
                  ),
                ],
              ),
            ],
            SizedBox(height: 12 * scale),
            Text("Feedback", style: Theme.of(context).textTheme.titleSmall),
            SizedBox(height: 6 * scale),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: _feedbackLines.isEmpty
                    ? Center(
                        child: Padding(
                          padding: EdgeInsets.all(12 * scale),
                          child: Text(
                            "Processing output will appear here.",
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: EdgeInsets.all(8 * scale),
                        itemCount: _feedbackLines.length,
                        itemBuilder: (context, i) {
                          return Padding(
                            padding: EdgeInsets.only(bottom: 4 * scale),
                            child: SelectableText(_feedbackLines[i]),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _onCancel,
          child: const Text("Close"),
        ),
        FilledButton(
          onPressed: importResetHandler,
          child: Text(_imported ? "Reset" : "Import"),
        ),
        OutlinedButton(
          onPressed: viewEnabled ? onView : null,
          child: const Text("View"),
        ),
      ],
    );
  }
}
