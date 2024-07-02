/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/data/ranking/project_manager.dart';

class EnterNameDialog extends StatefulWidget {
  const EnterNameDialog({Key? key, this.initial}) : super(key: key);

  final String? initial;

  @override
  State<EnterNameDialog> createState() => _EnterNameDialogState();
}

class _EnterNameDialogState extends State<EnterNameDialog> {
  late TextEditingController nameController;
  String _errorText = "";
  bool confirm = false;
  bool confirmed = false;
  
  @override
  void initState() {
    super.initState();

    nameController = TextEditingController(text: widget.initial);
    nameController.addListener(() { 
      if(RatingProjectManager().projectExists(nameController.text)) {
        setState(() {
          confirm = true;
          _errorText = "A project with that name exists. Tap 'OK' twice to confirm overwrite.";
        });
      }
      else {
        setState(() {
          confirm = false;
          confirmed = false;
          _errorText = "";
        });
      }
    });

    _initialCheck();
  }

  void _initialCheck() async {
    await RatingProjectManager().ready;
    if(widget.initial != null && RatingProjectManager().projectExists(widget.initial!)) {
      setState(() {
        confirm = true;
        _errorText = "A project with that name exists. Tap 'OK' twice to confirm overwrite.";
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("Set Project Name"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: 400),
          Text(_errorText, style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: Theme.of(context).errorColor)),
          TextField(
            keyboardType: TextInputType.text,
            decoration: InputDecoration(
              hintText: "Project Name"
            ),
            controller: nameController,
          )
        ],
      ),
      actions: [
        TextButton(
          child: Text("CANCEL"),
          onPressed: () {
            Navigator.of(context).pop("");
          },
        ),
        TextButton(
          child: Text("OK"),
          onPressed: () {
            if(nameController.text.length == 0) {
              setState(() {
                _errorText = "String is empty";
              });
            }

            if(confirm && confirmed) {
              Navigator.of(context).pop(nameController.text);
            }
            else if(confirm && !confirmed) {
              confirmed = true;
              setState(() {
                _errorText = "Tap again to confirm.";
              });
            }
            else {
              Navigator.of(context).pop(nameController.text);
            }
          },
        )
      ],
    );
  }
}
