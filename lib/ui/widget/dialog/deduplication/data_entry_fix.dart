import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/action.dart';

class AddDataEntryFixDialog extends StatefulWidget {
  const AddDataEntryFixDialog({super.key});

  @override
  State<AddDataEntryFixDialog> createState() => _AddDataEntryFixDialogState();

  static Future<DeduplicationAction?> show(BuildContext context) async {
    return showDialog<DeduplicationAction>(context: context, builder: (context) => const AddDataEntryFixDialog());
  }
}

class _AddDataEntryFixDialogState extends State<AddDataEntryFixDialog> {
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Data Entry Fix"),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL")),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("SAVE")),
      ],
    );
  }
}