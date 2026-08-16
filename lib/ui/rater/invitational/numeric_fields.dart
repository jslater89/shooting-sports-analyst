/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "package:flutter/material.dart";
import "package:flutter/services.dart";

class IntTextField extends StatefulWidget {
  const IntTextField({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
    this.width = 80,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final String? label;
  final double width;

  @override
  State<IntTextField> createState() => _IntTextFieldState();
}

class _IntTextFieldState extends State<IntTextField> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value.toString());
  }

  @override
  void didUpdateWidget(IntTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if(widget.value != oldWidget.value && widget.value.toString() != _controller.text) {
      _controller.text = widget.value.toString();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      child: TextField(
        controller: _controller,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          labelText: widget.label,
          isDense: true,
        ),
        onChanged: (value) {
          final parsed = int.tryParse(value);
          if(parsed != null) {
            widget.onChanged(parsed);
          }
        },
      ),
    );
  }
}

class DoubleTextField extends StatefulWidget {
  const DoubleTextField({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
    this.width = 80,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final String? label;
  final double width;

  @override
  State<DoubleTextField> createState() => _DoubleTextFieldState();
}

class _DoubleTextFieldState extends State<DoubleTextField> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _format(widget.value));
  }

  @override
  void didUpdateWidget(DoubleTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if(widget.value != oldWidget.value && _controller.text != _format(widget.value)) {
      _controller.text = _format(widget.value);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _format(double value) {
    if(value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value.toString();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      child: TextField(
        controller: _controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: widget.label,
          isDense: true,
        ),
        onChanged: (value) {
          final parsed = double.tryParse(value);
          if(parsed != null) {
            widget.onChanged(parsed);
          }
        },
      ),
    );
  }
}
