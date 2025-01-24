/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/action.dart';
import 'package:shooting_sports_analyst/ui/text_styles.dart';

class AddMappingDialog extends StatefulWidget {
  const AddMappingDialog({super.key, required this.memberNumbers, this.coveredMemberNumbers = const [], this.editAction});

  final List<String> memberNumbers;
  final List<String> coveredMemberNumbers;
  final UserMapping? editAction;

  @override
  State<AddMappingDialog> createState() => _AddMappingDialogState();

  static Future<UserMapping?> show(BuildContext context, List<String> memberNumbers, {List<String> coveredMemberNumbers = const []}) async {
    return showDialog<UserMapping>(context: context, builder: (context) => AddMappingDialog(memberNumbers: memberNumbers, coveredMemberNumbers: coveredMemberNumbers));
  }

  static Future<UserMapping?> edit(BuildContext context, UserMapping action, List<String> memberNumbers, {List<String> coveredMemberNumbers = const []}) async {
    return showDialog<UserMapping>(context: context, builder: (context) => AddMappingDialog(editAction: action, memberNumbers: memberNumbers, coveredMemberNumbers: coveredMemberNumbers));
  }
}

class _AddMappingDialogState extends State<AddMappingDialog> {
  var sourceController = TextEditingController();
  var targetController = TextEditingController();

  var sourceFocusNode = FocusNode();
  var targetFocusNode = FocusNode();

  String? sourceErrorText;
  String? targetErrorText;
  List<String> coveredNumbers = [];

  List<String> sources = [];

  @override
  void initState() {
    super.initState();
    coveredNumbers = [...widget.coveredMemberNumbers];
    sourceController.addListener(() {
      setState(() {
        sourceErrorText = null;
      });
    });
    targetController.addListener(() {
      setState(() {
        targetErrorText = null;
      });
    });
    if(widget.editAction != null) {
      sources = widget.editAction!.sourceNumbers;
      targetController.text = widget.editAction!.targetNumber;
    }
  }

  bool validate() {
    if(sources.isEmpty) {
      setState(() {
        sourceErrorText = "No sources selected";
      });
      return false;
    }
    if(targetController.text.isEmpty) {
      setState(() {
        targetErrorText = "No target selected";
      });
      return false;
    }
    if(sources.contains(targetController.text)) {
      setState(() {
        targetErrorText = "Target is a source";
      });
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Add user mapping"),
      content: FocusTraversalGroup(
        policy: WidgetOrderTraversalPolicy(),
        child: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  "User mappings tie several valid source numbers (in the left column) to a single target number (in the right column). " +
                  "Specify user mappings to tie a competitor's actual member numbers together, in the event that the automatic detection " +
                  "algorithm fails to match them. To correct typos or other data entry errors, use data entry fixes instead.",
                  style: TextStyles.bodyMedium(context),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 240,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.max,
                          crossAxisAlignment: CrossAxisAlignment.start,
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
                                width: 190,
                                errorText: sourceErrorText,
                                onSelected: (value) {
                                  if(value != null) {
                                    sourceController.text = value;
                                    setState(() {
                                      sourceErrorText = null;
                                      coveredNumbers.add(value);
                                    });
                                  }
                                },
                                requestFocusOnTap: true,
                                label: const Text("Source"),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: IconButton(padding: const EdgeInsets.all(6), iconSize: 20, icon: const Icon(Icons.add_circle_outline), onPressed: () {
                                if(!sources.contains(sourceController.text)) {
                                  setState(() {
                                    sources.add(sourceController.text);
                                    sourceErrorText = null;
                                  });
                                }
                              }),
                            ),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: Divider(thickness: 1, height: 1),
                        ),
                        for(var source in sources)
                          Row(
                            children: [
                              Text(source, style: Theme.of(context).textTheme.bodyMedium),
                              IconButton(padding: const EdgeInsets.all(6), iconSize: 20, icon: const Icon(Icons.remove_circle_outline), onPressed: () {
                                setState(() {
                                  sources.remove(source);
                                });
                              }),
                            ],
                          ),
                        if(sources.isEmpty)
                          Text("No sources", style: Theme.of(context).textTheme.bodyMedium),
                      ],
                    ),
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
                    errorText: targetErrorText,
                    onSelected: (value) {
                      if(value != null) {
                        targetController.text = value;
                        setState(() {
                          coveredNumbers.add(value);
                          targetErrorText = null;
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
              Navigator.pop(context, UserMapping(
                sourceNumbers: sources,
                targetNumber: targetController.text,
              ));
            }
          }
        )
      ],
    );
  }
}