import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/action.dart';

class AddMappingDialog extends StatefulWidget {
  const AddMappingDialog({super.key});

  @override
  State<AddMappingDialog> createState() => _AddMappingDialogState();

  static Future<DeduplicationAction?> show(BuildContext context) async {
    return showDialog<DeduplicationAction>(context: context, builder: (context) => const AddMappingDialog());
  }
}

class _AddMappingDialogState extends State<AddMappingDialog> {
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Member Number Mapping"),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL")),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("SAVE")),
      ],
    );
  }
}