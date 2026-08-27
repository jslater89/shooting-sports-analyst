/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shooting_sports_analyst/util.dart';

/// A dialog that lets the user pick a date range via two text fields or by opening
/// a calendar with [showDatePicker]. Uses [dateFormat] for display and parsing, or
/// [programmerYmdFormat] if null.
class SSADateRangePickerDialog extends StatefulWidget {
  const SSADateRangePickerDialog({
    super.key,
    this.startLimit,
    this.endLimit,
    this.initialStart,
    this.initialEnd,
    this.dateFormat,
  });

  /// Earliest selectable date (used as firstDate in the date picker).
  final DateTime? startLimit;
  /// Latest selectable date (used as lastDate in the date picker).
  final DateTime? endLimit;
  /// Initial start date shown in the dialog.
  final DateTime? initialStart;
  /// Initial end date shown in the dialog.
  final DateTime? initialEnd;
  /// Format for displaying and parsing dates. Defaults to [programmerYmdFormat] if null.
  final DateFormat? dateFormat;

  @override
  State<SSADateRangePickerDialog> createState() => _SSADateRangePickerDialogState();

  static Future<(DateTime, DateTime)?> show(
    BuildContext context, {
    DateTime? startLimit,
    DateTime? endLimit,
    DateTime? initialStart,
    DateTime? initialEnd,
    DateFormat? dateFormat,
    bool barrierDismissible = true,
    bool useRootNavigator = false,
  }) {
    return showDialog<(DateTime, DateTime)?>(
      context: context,
      useRootNavigator: useRootNavigator,
      barrierDismissible: barrierDismissible,
      builder: (context) => SSADateRangePickerDialog(
        startLimit: startLimit,
        endLimit: endLimit,
        initialStart: initialStart,
        initialEnd: initialEnd,
        dateFormat: dateFormat,
      ),
    );
  }
}

class _SSADateRangePickerDialogState extends State<SSADateRangePickerDialog> {
  late final TextEditingController _startController;
  late final TextEditingController _endController;
  final FocusNode _startFocusNode = FocusNode();
  final FocusNode _endFocusNode = FocusNode();

  DateTime? _start;
  DateTime? _end;
  String? _startError;
  String? _endError;

  DateTime get _firstDate =>
      widget.startLimit ?? practicalShootingZeroDate;
  DateTime get _lastDate => widget.endLimit ?? DateTime.now();
  DateFormat get _format => widget.dateFormat ?? programmerYmdFormat;

  @override
  void initState() {
    super.initState();
    _start = widget.initialStart;
    _end = widget.initialEnd;
    final format = _format;
    _startController = TextEditingController(
      text: widget.initialStart != null
          ? format.format(widget.initialStart!)
          : "",
    );
    _endController = TextEditingController(
      text: widget.initialEnd != null
          ? format.format(widget.initialEnd!)
          : "",
    );
    _startFocusNode.addListener(() {
      if (!_startFocusNode.hasFocus) {
        _parseStart(_startController.text);
      }
    });
    _endFocusNode.addListener(() {
      if (!_endFocusNode.hasFocus) {
        _parseEnd(_endController.text);
      }
    });
  }

  @override
  void dispose() {
    _startFocusNode.dispose();
    _endFocusNode.dispose();
    _startController.dispose();
    _endController.dispose();
    super.dispose();
  }

  void _parseStart(String text) {
    if (text.isEmpty) {
      setState(() {
        _start = null;
        _startError = null;
      });
      return;
    }
    try {
      final d = _format.parse(text);
      final clamped = _clampToLimits(d);
      setState(() {
        _start = clamped;
        _startError = null;
        _startController.text = _format.format(clamped);
      });
    }
    catch (_) {
      setState(() {
        _startError = "Invalid date";
      });
    }
  }

  void _parseEnd(String text) {
    if (text.isEmpty) {
      setState(() {
        _end = null;
        _endError = null;
      });
      return;
    }
    try {
      final d = _format.parse(text);
      final clamped = _clampToLimits(d);
      setState(() {
        _end = clamped;
        _endError = null;
        _endController.text = _format.format(clamped);
      });
    }
    catch (_) {
      setState(() {
        _endError = "Invalid date";
      });
    }
  }

  DateTime _clampToLimits(DateTime d) {
    if (d.isBefore(_firstDate)) {
      return _firstDate;
    }
    if (d.isAfter(_lastDate)) {
      return _lastDate;
    }
    return d;
  }

  Future<void> _pickStart() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _start ?? _firstDate,
      firstDate: _firstDate,
      lastDate: _lastDate,
      initialEntryMode: DatePickerEntryMode.calendar,
    );
    if (picked != null && mounted) {
      final clamped = _clampToLimits(picked);
      setState(() {
        _start = clamped;
        _startError = null;
        _startController.text = _format.format(clamped);
      });
    }
  }

  Future<void> _pickEnd() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _end ?? _lastDate,
      firstDate: _firstDate,
      lastDate: _lastDate,
      initialEntryMode: DatePickerEntryMode.calendar,
    );
    if (picked != null && mounted) {
      final clamped = _clampToLimits(picked);
      setState(() {
        _end = clamped;
        _endError = null;
        _endController.text = _format.format(clamped);
      });
    }
  }

  bool get _canSubmit {
    if (_start == null || _end == null) {
      return false;
    }
    if (_start!.isAfter(_end!)) {
      return false;
    }
    if (widget.startLimit != null && (_start!.isBefore(widget.startLimit!) || _end!.isBefore(widget.startLimit!))) {
      return false;
    }
    if (widget.endLimit != null && (_start!.isAfter(widget.endLimit!) || _end!.isAfter(widget.endLimit!))) {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final summaryText = _start != null && _end != null
        ? "${_format.format(_start!)} – ${_format.format(_end!)}"
        : "(none selected)";

    return AlertDialog(
      title: const Text("Select Date Range"),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(summaryText, style: Theme.of(context).textTheme.bodyLarge, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _startController,
                    focusNode: _startFocusNode,
                    decoration: InputDecoration(
                      labelText: "Start",
                      errorText: _startError,
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.calendar_month),
                        onPressed: _pickStart,
                      ),
                    ),
                    onFieldSubmitted: _parseStart,
                    onTapOutside: (_) => _parseStart(_startController.text),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _endController,
                    focusNode: _endFocusNode,
                    decoration: InputDecoration(
                      labelText: "End",
                      errorText: _endError,
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.calendar_month),
                        onPressed: _pickEnd,
                      ),
                    ),
                    onFieldSubmitted: _parseEnd,
                    onTapOutside: (_) => _parseEnd(_endController.text),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop<(DateTime, DateTime)?>(null),
          child: const Text("CANCEL"),
        ),
        TextButton(
          onPressed: _canSubmit
              ? () => Navigator.of(context).pop((_start!, _end!))
              : null,
          child: const Text("OK"),
        ),
      ],
    );
  }
}
