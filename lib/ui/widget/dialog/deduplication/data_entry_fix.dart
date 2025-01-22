import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/action.dart';

class AddDataEntryFixDialog extends StatefulWidget {
  const AddDataEntryFixDialog({super.key, required this.deduplicatorName, required this.memberNumbers, this.coveredMemberNumbers = const [], this.editAction});

  final String deduplicatorName;
  final List<String> memberNumbers;
  final List<String> coveredMemberNumbers;
  final DataEntryFix? editAction;

  @override
  State<AddDataEntryFixDialog> createState() => _AddDataEntryFixDialogState();

  static Future<DataEntryFix?> show(BuildContext context, String deduplicatorName, List<String> memberNumbers, {List<String> coveredMemberNumbers = const []}) async {
    return showDialog<DataEntryFix>(context: context, builder: (context) => AddDataEntryFixDialog(deduplicatorName: deduplicatorName, memberNumbers: memberNumbers, coveredMemberNumbers: coveredMemberNumbers));
  }

  static Future<DataEntryFix?> edit(BuildContext context, DataEntryFix action, List<String> memberNumbers, {List<String> coveredMemberNumbers = const []}) async {
    return showDialog<DataEntryFix>(context: context, builder: (context) => AddDataEntryFixDialog(editAction: action, deduplicatorName: action.deduplicatorName, memberNumbers: memberNumbers, coveredMemberNumbers: coveredMemberNumbers));
  }
}

class _AddDataEntryFixDialogState extends State<AddDataEntryFixDialog> {
  var invalidController = TextEditingController();
  var correctedController = TextEditingController();

  var invalidFocusNode = FocusNode();
  var correctedFocusNode = FocusNode();

  var invalidErrorText = "";
  var correctedErrorText = "";
  List<String> coveredNumbers = [];

  @override
  void initState() {
    super.initState();
    coveredNumbers = [...widget.coveredMemberNumbers];
    invalidController.addListener(() {
      setState(() {
        invalidErrorText = "";
      });
    });
    correctedController.addListener(() {
      setState(() {
        correctedErrorText = "";
      });
    });
    if(widget.editAction != null) {
      invalidController.text = widget.editAction!.sourceNumber;
      correctedController.text = widget.editAction!.targetNumber;
    }
  }

  bool validate() {
    if(invalidController.text.isEmpty) {
      setState(() {
        invalidErrorText = "Source number is required";
      });
      return false;
    }
    if(correctedController.text.isEmpty) {
      setState(() {
        correctedErrorText = "Target number is required";
      });
      return false;
    }
    if(invalidController.text == correctedController.text) {
      setState(() {
        correctedErrorText = "Source and target cannot be the same";
      });
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Data Entry Fix"),
      content: FocusTraversalGroup(
        policy: WidgetOrderTraversalPolicy(),
        child: SizedBox(
          width: 500,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              DropdownMenu<String>(
                dropdownMenuEntries: widget.memberNumbers.map((e) => 
                  DropdownMenuEntry(
                    value: e,
                    label: e,
                    style: widget.coveredMemberNumbers.contains(e) ? ButtonStyle(textStyle: MaterialStateProperty.all(TextStyle(color: Colors.green.shade600))) : null,
                  )
                ).toList(),
                controller: invalidController,
                width: 200,
                onSelected: (value) {
                  if(value != null) {
                    invalidController.text = value;
                    setState(() {
                      coveredNumbers.add(value);
                    });
                  }
                },
                requestFocusOnTap: true,
                label: const Text("Incorrect"),
              ),
              const SizedBox(width: 10),
              IconButton(
                icon: const Icon(Icons.swap_horiz),
                onPressed: () {
                  var temp = invalidController.text;
                  invalidController.text = correctedController.text;
                  correctedController.text = temp;
                },
              ),
              const SizedBox(width: 10),
              DropdownMenu<String>(
                dropdownMenuEntries: widget.memberNumbers.map((e) => 
                  DropdownMenuEntry(
                    value: e,
                    label: e,
                    style: coveredNumbers.contains(e) ? ButtonStyle(textStyle: MaterialStateProperty.all(TextStyle(color: Colors.green.shade600))) : null,
                  )
                ).toList(),
                controller: correctedController,
                width: 200,
                onSelected: (value) {
                  if(value != null) {
                    correctedController.text = value;
                    setState(() {
                      coveredNumbers.add(value);
                    });
                  }
                },
                requestFocusOnTap: true,
                label: const Text("Corrected"),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL")),
        TextButton(
          child: Text("SAVE"),
          onPressed: () {
            if(validate()) {
              Navigator.pop(context, DataEntryFix(
                deduplicatorName: widget.deduplicatorName,
                sourceNumber: invalidController.text,
                targetNumber: correctedController.text,
              ));
            }
          }
        )
      ],
    );
  }
}