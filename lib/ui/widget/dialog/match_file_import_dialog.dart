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
import "package:shooting_sports_analyst/closed_sources/psv2/matchdef/match_info_zip.dart";
import "package:shooting_sports_analyst/closed_sources/psv2/psv2_source.dart";
import "package:shooting_sports_analyst/config/config.dart";
import "package:shooting_sports_analyst/data/database/analyst_database.dart";
import "package:shooting_sports_analyst/data/database/extensions/future_match.dart";
import "package:shooting_sports_analyst/data/database/schema/match_prep/match.dart";
import "package:shooting_sports_analyst/data/import/type_detector.dart";
import "package:shooting_sports_analyst/data/source/auto_importer.dart";
import "package:shooting_sports_analyst/data/source/practiscore_report.dart";
import "package:shooting_sports_analyst/data/sport/builtins/uspsa.dart";
import "package:shooting_sports_analyst/data/sport/match/match.dart";
import "package:shooting_sports_analyst/logger.dart";
import "package:shooting_sports_analyst/ui/result_page.dart";

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

  /// True once the import process has completed successfully; replaces
  /// the 'import' button with a 'reset' button.
  bool _imported = false;
  ShootingMatch? _processedMatch;
  FutureMatch? _processedFutureMatch;

  /// Stub: true once a file is chosen. Replace with "parse completed successfully" when processing exists.
  bool get _hasProcessedData => _processedMatch != null || _processedFutureMatch != null;

  String get _fileDisplayLabel {
    final f = _pickedFile;
    if (f == null) {
      return "No file selected";
    }
    return f.path?.isNotEmpty == true ? f.path! : f.name;
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(withData: false);
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
          _feedbackLines.add("Failed to detect file format");
        });
        return;
      }
      _feedbackLines.add("File format detected: ${format.label}, processing...");
      setState(() {
        _pickedFile = result.files.first;
      });

      await _processFile(file, format);
    } catch (e, st) {
      _log.e("File pick failed", error: e, stackTrace: st);
      if (mounted) {
        setState(() {
          _feedbackLines.add("Failed to pick file: $e");
        });
      }
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
        var result = await AutoImporter.getFutureMatchFromHtml(registrationHtml);
        if(result.isErr()) {
          setState(() {
            _feedbackLines.add("Failed to process match: ${result.unwrapErr().message}");
          });
          return;
        }
        setState(() {
          _processedFutureMatch = result.unwrap().$1;
          _processedFutureMatch!.newRegistrations = result.unwrap().$2;
          _feedbackLines.add("Match processed successfully (${_processedFutureMatch!.newRegistrations.length} registrations)");
        });
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
        height: 420 * scale,
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
