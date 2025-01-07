/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/data/ranking/rater.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/confirm_dialog.dart';
import 'package:shooting_sports_analyst/util.dart';

class MemberNumberBlacklistDialog extends StatefulWidget {
  const MemberNumberBlacklistDialog({
    Key? key,
    this.initialMap = const {},
    required this.title,
    this.helpText,
    this.sourceHintText,
    this.targetHintText,
    this.width = 600,
  }) : super(key: key);

  final Map<String, List<String>> initialMap;
  final String title;
  final String? helpText;
  final String? sourceHintText;
  final String? targetHintText;
  final double width;

  @override
  State<MemberNumberBlacklistDialog> createState() => _MemberNumberBlacklistDialogState();
}

class _MemberNumberBlacklistDialogState extends State<MemberNumberBlacklistDialog> {
  Map<String, List<String>> mappings = {};
  String errorText = "";

  var sourceController = TextEditingController();
  var targetController = TextEditingController();

  var targetFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();

    mappings.addAll(widget.initialMap);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      scrollable: true,
      content: SizedBox(
        width: widget.width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if(widget.helpText != null) Text(widget.helpText!),
            Text(errorText, style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: Theme.of(context).errorColor)),
            SizedBox(
              width: widget.width / 1.5,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: sourceController,
                      decoration: InputDecoration(
                          hintText: widget.sourceHintText,
                          suffix: IconButton(
                            icon: Icon(Icons.forward),
                            onPressed: () {
                              advance();
                            },
                          )
                      ),
                      onSubmitted: (input) {
                        advance();
                      },
                    ),
                  ),
                  SizedBox(
                    width: 5,
                  ),
                  Expanded(
                    child: TextField(
                      focusNode: targetFocusNode,
                      controller: targetController,
                      decoration: InputDecoration(
                          hintText: widget.targetHintText,
                          suffix: IconButton(
                            icon: Icon(Icons.add),
                            onPressed: () {
                              submit(sourceController.text, targetController.text);
                            },
                          )
                      ),
                      onSubmitted: (input) {
                        submit(sourceController.text, input);
                      },
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 8),
            for(var source in mappings.keys) SizedBox(
              width: widget.width / 3,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                mainAxisSize: MainAxisSize.max,
                children: [
                  Text("$source to ${mappings[source]!}"),
                  SizedBox(width: 10),
                  IconButton(
                    icon: Icon(Icons.remove),
                    onPressed: () {
                      setState(() {
                        mappings.remove(source);
                      });
                    },
                  )
                ],
              ),
            )
          ],
        ),
      ),
      actions: [
        TextButton(
          child: Text("CANCEL"),
          onPressed: () {
            Navigator.of(context).pop(null);
          },
        ),
        TextButton(
          child: Text("OK"),
          onPressed: () async {
            if(sourceController.text.isNotEmpty && targetController.text.isNotEmpty) {
              var confirm = await showDialog<bool>(context: context, builder: (c) =>
                  ConfirmDialog(
                    content: Text("The input field contains unsubmitted information. Do you want to discard it?"),
                    positiveButtonLabel: "DISCARD",
                  ));
              if(confirm == null || !confirm) {
                return;
              }
            }
            Navigator.of(context).pop(mappings);
          },
        )
      ],
    );
  }

  void advance() {
    targetFocusNode.requestFocus();
  }

  void submit(String source, String target) {
    if(!validate(source)) return;
    if(!validate(target)) return;

    source = Rater.processMemberNumber(source);
    target = Rater.processMemberNumber(target);

    if(source == target) {
      setState(() {
        errorText = "Cannot map a member number to itself!";
      });
      return;
    }

    setState(() {
      mappings.addToList(source, target);
      sourceController.clear();
      targetController.clear();
    });
  }

  bool validate(String input) {
    if(!input.contains(RegExp(r"[0-9]+"))) {
      setState(() {
        errorText = "Member number must contain at least one number.";
      });
      return false;
    }
    else {
      setState(() {
        errorText = "";
      });
      return true;
    }
  }
}