import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/action.dart';
import 'package:shooting_sports_analyst/ui/text_styles.dart';

class AddBlacklistEntryDialog extends StatefulWidget {
  const AddBlacklistEntryDialog({super.key, required this.memberNumbers, this.coveredMemberNumbers = const [], this.editAction});

  final List<String> memberNumbers;
  final List<String> coveredMemberNumbers;
  final Blacklist? editAction;
  @override
  State<AddBlacklistEntryDialog> createState() => _AddBlacklistEntryDialogState();

  static Future<Blacklist?> show(BuildContext context, List<String> memberNumbers, {List<String> coveredMemberNumbers = const []}) async {
    return showDialog<Blacklist>(context: context, builder: (context) => AddBlacklistEntryDialog(memberNumbers: memberNumbers, coveredMemberNumbers: coveredMemberNumbers));
  }

  static Future<Blacklist?> edit(BuildContext context, Blacklist action, List<String> memberNumbers, {List<String> coveredMemberNumbers = const []}) async {
    return showDialog<Blacklist>(context: context, builder: (context) => AddBlacklistEntryDialog(memberNumbers: memberNumbers, coveredMemberNumbers: coveredMemberNumbers, editAction: action));
  }
}

class _AddBlacklistEntryDialogState extends State<AddBlacklistEntryDialog> {
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
    if(widget.editAction != null) {
      sourceController.text = widget.editAction!.sourceNumber;
      targetController.text = widget.editAction!.targetNumber;
    }
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
      title: const Text("Add blacklist entry"),
      content: FocusTraversalGroup(
        policy: WidgetOrderTraversalPolicy(),
        child: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Blacklist entries prevent a deduplicator from making automatic associations between two member numbers. " +
                "Add a blacklist entry between two member numbers if their competitors share a deduplicator name, but " +
                "are not the same person. When adding a blacklist entry alongside a data entry fix or user mapping, the blacklist " +
                "entry must point to the target number, not the source number(s).",
                style: TextStyles.bodyMedium(context),
              ),
              Row(
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
                    controller: sourceController,
                    width: 200,
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
                  const SizedBox(width: 10),
                  DropdownMenu<String>(
                    dropdownMenuEntries: widget.memberNumbers.map((e) => 
                      DropdownMenuEntry(
                        value: e,
                        label: e,
                        style: coveredNumbers.contains(e) ? ButtonStyle(textStyle: MaterialStateProperty.all(TextStyle(color: Colors.green.shade600))) : null,
                      )
                    ).toList(),
                    controller: targetController,
                    width: 200,
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
                ],
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
              Navigator.pop(context, Blacklist(
                sourceNumber: sourceController.text,
                targetNumber: targetController.text,
                bidirectional: true,
              ));
            }
          }
        )
      ],
    );
  }
}