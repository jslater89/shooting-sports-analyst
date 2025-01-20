import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/action.dart';

class AddMappingDialog extends StatefulWidget {
  const AddMappingDialog({super.key, required this.memberNumbers, this.coveredMemberNumbers = const []});

  final List<String> memberNumbers;
  final List<String> coveredMemberNumbers;
  @override
  State<AddMappingDialog> createState() => _AddMappingDialogState();

  static Future<DeduplicationAction?> show(BuildContext context, List<String> memberNumbers, {List<String> coveredMemberNumbers = const []}) async {
    return showDialog<DeduplicationAction>(context: context, builder: (context) => AddMappingDialog(memberNumbers: memberNumbers, coveredMemberNumbers: coveredMemberNumbers));
  }
}

class _AddMappingDialogState extends State<AddMappingDialog> {
  var sourceController = TextEditingController();
  var targetController = TextEditingController();

  var sourceFocusNode = FocusNode();
  var targetFocusNode = FocusNode();

  var sourceErrorText = "";
  var targetErrorText = "";
  List<String> coveredNumbers = [];

  @override
  void initState() {
    super.initState();
    coveredNumbers = [...widget.coveredMemberNumbers];
    sourceController.addListener(() {
      setState(() {
        sourceErrorText = "";
      });
    });
    targetController.addListener(() {
      setState(() {
        targetErrorText = "";
      });
    });
  }

  bool validate() {
    if(sourceController.text.isEmpty) {
      setState(() {
        sourceErrorText = "Source number is required";
      });
      return false;
    }
    if(targetController.text.isEmpty) {
      setState(() {
        targetErrorText = "Target number is required";
      });
      return false;
    }
    if(sourceController.text == targetController.text) {
      setState(() {
        targetErrorText = "Source and target cannot be the same";
      });
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("User Mapping"),
      content: FocusTraversalGroup(
        policy: WidgetOrderTraversalPolicy(),
        child: Row(
          children: [
            Expanded(
              child: DropdownMenu<String>(
                dropdownMenuEntries: widget.memberNumbers.map((e) => 
                  DropdownMenuEntry(
                    value: e,
                    label: e,
                    style: widget.coveredMemberNumbers.contains(e) ? ButtonStyle(textStyle: MaterialStateProperty.all(TextStyle(color: Colors.green.shade600))) : null,
                  )
                ).toList(),
                controller: sourceController,
                onSelected: (value) {
                  if(value != null) {
                    sourceController.text = value;
                    setState(() {
                      coveredNumbers.add(value);
                    });
                  }
                },
                requestFocusOnTap: true,
                label: const Text("Source"),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownMenu<String>(
                dropdownMenuEntries: widget.memberNumbers.map((e) => 
                  DropdownMenuEntry(
                    value: e,
                    label: e,
                    style: coveredNumbers.contains(e) ? ButtonStyle(textStyle: MaterialStateProperty.all(TextStyle(color: Colors.green.shade600))) : null,
                  )
                ).toList(),
                controller: targetController,
                onSelected: (value) {
                  if(value != null) {
                    targetController.text = value;
                    setState(() {
                      coveredNumbers.add(value);
                    });
                  }
                },
                requestFocusOnTap: true,
                label: const Text("Target"),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL")),
        TextButton(
          child: Text("SAVE"),
          onPressed: () {
            if(validate()) {
              Navigator.pop(context, UserMapping(
                sourceNumbers: [sourceController.text],
                targetNumber: targetController.text,
              ));
            }
          }
        )
      ],
    );
  }
}