/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/data/ranking/project_manager.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/confirm_dialog.dart';

class SelectProjectDialog extends StatefulWidget {
  const SelectProjectDialog({Key? key, required this.projectNames}) : super(key: key);

  final List<String> projectNames;

  @override
  State<SelectProjectDialog> createState() => _SelectProjectDialogState();
}

class _SelectProjectDialogState extends State<SelectProjectDialog> {
  List<String> _localNames = [];
  @override
  void initState() {
    super.initState();
    _localNames = widget.projectNames;
  }
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("Select Project"),
      content: SizedBox(
        width: 600,
        child: ListView.builder(
          shrinkWrap: true,
          itemBuilder: (context, i) {
            var name = _localNames[i];
            return ListTile(
              title: Text(name),
              trailing: IconButton(
                icon: Icon(Icons.delete),
                onPressed: () async {
                  var delete = await showDialog<bool>(context: context, builder: (context) {
                    return ConfirmDialog(content: Text("Delete $name?"));
                  });

                  if(delete ?? false) {
                    RatingProjectManager().deleteProject(name);
                    setState(() {
                      _localNames.remove(name);
                    });
                  }
                },
              ),
              onTap: () {
                Navigator.of(context).pop(name);
              },
            );
          },
          itemCount: _localNames.length,
        ),
      ),
    );
  }
}
