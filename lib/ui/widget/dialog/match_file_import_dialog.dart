/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "package:file_picker/file_picker.dart";
import "package:flutter/material.dart";
import "package:shooting_sports_analyst/config/config.dart";
import "package:shooting_sports_analyst/logger.dart";
import "package:shooting_sports_analyst/ui/empty_scaffold.dart";

final _log = SSALogger("MatchFileImportDialog");

/// File formats offered for match import (labels match product wording).
enum MatchImportFormat {
  practiscoreReportTxt,
  practiscorePsc,
  practiscoreRegistrationZip,
  miff,
  riff,
  autoDetect,
}

extension MatchImportFormatLabels on MatchImportFormat {
  String get label {
    switch (this) {
      case MatchImportFormat.practiscoreReportTxt:
        return "Practiscore report.txt";
      case MatchImportFormat.practiscorePsc:
        return "Practiscore .psc";
      case MatchImportFormat.practiscoreRegistrationZip:
        return "Practiscore registration page source zip";
      case MatchImportFormat.miff:
        return "MIFF";
      case MatchImportFormat.riff:
        return "RIFF";
      case MatchImportFormat.autoDetect:
        return "Auto-detect";
    }
  }
}

/// Whether the format can be opened in a results-style viewer once data exists.
/// TODO: Expand when more viewers exist; may also depend on parsed type when [MatchImportFormat.autoDetect] is used.
bool matchImportFormatIsViewable(MatchImportFormat format) {
  return format == MatchImportFormat.practiscoreReportTxt;
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
  MatchImportFormat _format = MatchImportFormat.autoDetect;
  final List<String> _feedbackLines = [];

  /// Stub: true once a file is chosen. Replace with "parse completed successfully" when processing exists.
  bool get _hasProcessedData => _pickedFile != null;

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
      setState(() {
        _pickedFile = result.files.first;
      });
    } catch (e, st) {
      _log.e("File pick failed", error: e, stackTrace: st);
      if (mounted) {
        setState(() {
          _feedbackLines.add("Failed to pick file: $e");
        });
      }
    }
  }

  void _onCancel() {
    Navigator.of(context).pop();
  }

  void _onImportStub() {
    setState(() {
      _pickedFile = null;
      _format = MatchImportFormat.autoDetect;
      _feedbackLines
        ..clear()
        ..add("Import is not implemented yet. Dialog was reset.");
    });
  }

  Future<void> _onViewStub() async {
    if (!_hasProcessedData || !matchImportFormatIsViewable(_format)) {
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => const _MatchImportViewerPlaceholderPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scale = ChangeNotifierConfigLoader().uiConfig.uiScaleFactor;
    final importEnabled = _hasProcessedData;
    final viewEnabled = _hasProcessedData && matchImportFormatIsViewable(_format);

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
                child: DropdownButton<MatchImportFormat>(
                  isExpanded: true,
                  value: _format,
                  items: MatchImportFormat.values
                      .map(
                        (e) => DropdownMenuItem<MatchImportFormat>(
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
          child: const Text("Cancel"),
        ),
        FilledButton(
          onPressed: importEnabled ? _onImportStub : null,
          child: const Text("Import"),
        ),
        OutlinedButton(
          onPressed: viewEnabled ? _onViewStub : null,
          child: const Text("View"),
        ),
      ],
    );
  }
}

class _MatchImportViewerPlaceholderPage extends StatelessWidget {
  const _MatchImportViewerPlaceholderPage();

  @override
  Widget build(BuildContext context) {
    return EmptyScaffold(
      title: "Match Import Viewer",
      child: const Center(
        child: Text("Placeholder viewer (import pipeline not wired)."),
      ),
    );
  }
}
