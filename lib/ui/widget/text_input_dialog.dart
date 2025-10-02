import 'package:flutter/material.dart';

class TextInputDialog extends StatefulWidget {
  final String title;
  final String? initialValue;

  const TextInputDialog({super.key, required this.title, this.initialValue});

  @override
  State<TextInputDialog> createState() => _TextInputDialogState();

  static Future<String?> show(BuildContext context, {required String title, String? initialValue}) {
    return showDialog<String>(
      context: context,
      builder: (context) => TextInputDialog(title: title, initialValue: initialValue),
    );
  }
}

class _TextInputDialogState extends State<TextInputDialog> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue ?? "");
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop(_controller.text.trim().isEmpty ? null : _controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        onSubmitted: (_) => _submit(),
        decoration: const InputDecoration(
          hintText: "Enter text",
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text("CANCEL"),
        ),
        TextButton(
          onPressed: _submit,
          child: const Text("OK"),
        ),
      ],
    );
  }
}
