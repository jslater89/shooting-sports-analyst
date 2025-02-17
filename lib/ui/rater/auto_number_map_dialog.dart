/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/shooter_deduplicator.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/confirm_dialog.dart';
import 'package:shooting_sports_analyst/util.dart';

class AutoNumberMapDialog extends StatefulWidget {
  const AutoNumberMapDialog({
    Key? key,
    this.sport,
    required this.initialMappings,
    required this.title,
    this.helpText,
    this.sourceHintText,
    this.targetHintText,
    this.width = 600,
  }) : super(key: key);

  final Sport? sport;
  final List<DbMemberNumberMapping> initialMappings;
  final String title;
  final String? helpText;
  final String? sourceHintText;
  final String? targetHintText;
  final double width;

  @override
  State<AutoNumberMapDialog> createState() => _AutoNumberMapDialogState();
}

class _AutoNumberMapDialogState extends State<AutoNumberMapDialog> {
  List<DbMemberNumberMapping> mappings = [];
  List<DbMemberNumberMapping> filteredMappings = [];
  String errorText = "";

  var sourceController = TextEditingController();
  var targetController = TextEditingController();

  var sourceFilterController = TextEditingController();
  var targetFilterController = TextEditingController();

  var targetFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();

    mappings.addAll(widget.initialMappings);
    mappings.sort((a, b) => a.targetNumber.compareTo(b.targetNumber));
    filteredMappings = mappings;
    sourceFilterController.addListener(_applyFilters);
    targetFilterController.addListener(_applyFilters);
  }

  void _applyFilters() {
    if(sourceFilterController.text.isEmpty && targetFilterController.text.isEmpty) {
      setState(() {
        filteredMappings = mappings;
      });
    }
    else {
      setState(() {
        filteredMappings = mappings.where((mapping) {
          bool sourceMatches = sourceFilterController.text.isEmpty || mapping.sourceNumbers.any((source) => source.contains(sourceFilterController.text));
          bool targetMatches = targetFilterController.text.isEmpty || mapping.targetNumber.contains(targetFilterController.text);
          return sourceMatches && targetMatches;
        }).toList();
      });
    }
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
            SizedBox(height: 8),
            SizedBox(
              width: widget.width / 1.5,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Filter by...", style: Theme.of(context).textTheme.bodySmall),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: targetFilterController,
                              decoration: InputDecoration(
                                hintText: "Target",  
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 5,
                          ),
                          Expanded(
                            child: TextField(
                              controller: sourceFilterController,
                              decoration: InputDecoration(
                                hintText: "Source",  
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(height: 8),
            for(var mapping in filteredMappings) SizedBox(
              width: widget.width / 1.5,
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    mainAxisSize: MainAxisSize.max,
                    children: [
                      Text("${mapping.targetNumber}"),
                      Tooltip(
                        message: "Remove all mappings targeting ${mapping.targetNumber}",
                        child: IconButton(
                          icon: Icon(Icons.remove),
                          onPressed: () {
                            setState(() {
                              mappings.remove(mapping);
                            });
                          },
                        ),
                      )
                    ],
                  ),
                  for(var source in mapping.sourceNumbers)
                    Padding(
                      padding: const EdgeInsets.only(left: 24),
                      child: Row(
                        children: [
                          Tooltip(
                            message: "Remove the mapping from $source to ${mapping.targetNumber}",
                            child: IconButton(
                              icon: Icon(Icons.remove),
                              onPressed: () {
                                setState(() {
                                  mapping.sourceNumbers.remove(source);
                                });
                              },
                            ),
                          ),
                          Text(source),
                        ],
                      ),
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
}