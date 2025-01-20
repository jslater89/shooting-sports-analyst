/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/shooter_deduplicator.dart';
import 'package:shooting_sports_analyst/data/ranking/member_number_correction.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/confirm_dialog.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/member_number_collision_dialog.dart';

class MemberNumberCorrectionListDialog extends StatefulWidget {
  const MemberNumberCorrectionListDialog({
    Key? key,
    this.sport,
    required this.corrections,
    this.title = "Fix data entry errors",
    this.helpText = "Use this feature to correct one-off data entry errors. If John Doe mistakenly enters "
        "A99999 for his member number, but his member number is actually A88888, enter 'John Doe' in "
        "the left field, 'A99999' in the center field, and 'A88888' in the right field.",
    this.nameHintText = "Name",
    this.sourceHintText = "Invalid #",
    this.targetHintText = "Corrected #",
    this.width = 600,
  }) : super(key: key);

  final Sport? sport;
  final MemberNumberCorrectionContainer corrections;
  final String title;
  final String? nameHintText;
  final String? helpText;
  final String? sourceHintText;
  final String? targetHintText;
  final double width;

  @override
  State<MemberNumberCorrectionListDialog> createState() => _MemberNumberCorrectionListDialogState();
}

class _MemberNumberCorrectionListDialogState extends State<MemberNumberCorrectionListDialog> {
  String errorText = "";

  var nameController = TextEditingController();
  var sourceController = TextEditingController();
  var targetController = TextEditingController();

  var nameFocusNode = FocusNode();
  var sourceFocusNode = FocusNode();
  var targetFocusNode = FocusNode();

  var changed = false;

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
                      focusNode: nameFocusNode,
                      controller: nameController,
                      decoration: InputDecoration(
                          hintText: widget.nameHintText,
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
                      focusNode: sourceFocusNode,
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
                              submit(nameController.text, sourceController.text, targetController.text);
                            },
                          )
                      ),
                      onSubmitted: (input) {
                        submit(nameController.text, sourceController.text, input);
                      },
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 8),
            for(var correction in widget.corrections.all) SizedBox(
              width: widget.width / 1.5,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                mainAxisSize: MainAxisSize.max,
                children: [
                  Text("Use ${correction.correctedNumber} if ${correction.name} enters ${correction.invalidNumber}"),
                  SizedBox(width: 10),
                  IconButton(
                    icon: Icon(Icons.remove),
                    onPressed: () {
                      setState(() {
                        changed = true;
                        widget.corrections.remove(correction);
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
            Navigator.of(context).pop(changed);
          },
        ),
        TextButton(
          child: Text("OK"),
          onPressed: () async {
            if(nameController.text.isNotEmpty && sourceController.text.isNotEmpty && targetController.text.isNotEmpty) {
              var confirm = await showDialog<bool>(context: context, builder: (c) =>
                  ConfirmDialog(
                    content: Text("The input fields contain unsubmitted information. Do you want to discard it?"),
                    positiveButtonLabel: "DISCARD",
                  ));
              if(confirm == null || !confirm) {
                return;
              }
            }
            Navigator.of(context).pop(changed);
          },
        )
      ],
    );
  }

  void advance() {
    if(nameFocusNode.hasFocus) sourceFocusNode.requestFocus();
    else if(sourceFocusNode.hasFocus) targetFocusNode.requestFocus();
  }

  void submit(String name, String source, String target) {
    if(name.isEmpty) {
      setState(() {
        errorText = "Name cannot be empty!";
      });
      return;
    }
    if(!validate(source, allowEmpty: true)) return;
    if(!validate(target)) return;

    name = name.toLowerCase().replaceAll(RegExp(r"[^a-zA-Z0-9]"), "");
    source = widget.sport == null ? source : ShooterDeduplicator.numberProcessor(widget.sport!)(source);
    target = widget.sport == null ? target : ShooterDeduplicator.numberProcessor(widget.sport!)(target);

    if(source == target) {
      setState(() {
        errorText = "Cannot map a member number to itself!";
      });
      return;
    }

    setState(() {
      widget.corrections.add(MemberNumberCorrection(
        name: name,
        invalidNumber: source,
        correctedNumber: target,
      ));
      changed = true;
      nameController.clear();
      sourceController.clear();
      targetController.clear();
    });
  }

  bool validate(String input, {bool allowEmpty = false}) {
    if(allowEmpty && input.isEmpty) return true;
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