import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:uspsa_result_viewer/data/ranking/rater.dart';

class MemberNumberMapDialog extends StatefulWidget {
  const MemberNumberMapDialog({
    Key? key,
    this.initialMap = const {},
    required this.title,
    this.helpText,
    this.sourceHintText,
    this.targetHintText,
    this.width = 600,
  }) : super(key: key);

  final Map<String, String> initialMap;
  final String title;
  final String? helpText;
  final String? sourceHintText;
  final String? targetHintText;
  final double width;

  @override
  State<MemberNumberMapDialog> createState() => _MemberNumberMapDialogState();
}

class _MemberNumberMapDialogState extends State<MemberNumberMapDialog> {
  Map<String, String> mappings = {};
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
          onPressed: () {
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
      mappings[source] = target;
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