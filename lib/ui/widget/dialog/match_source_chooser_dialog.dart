/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/data/source/registered_sources.dart';
import 'package:shooting_sports_analyst/data/source/source.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';

class MatchSourceChooserDialog extends StatefulWidget {
  const MatchSourceChooserDialog({Key? key, this.hintText, required this.sources, this.title, this.descriptionText, this.validator}) : super(key: key);

  /// The title for the URL entry dialog.
  final String? title;
  /// The description text to show in the URL dialog, above the entry dialog.
  final String? descriptionText;
  /// The hint text to show in the URL dialog.
  final String? hintText;
  /// The list of match sources to allow.
  final List<MatchSource> sources;
  final String? Function(String)? validator;

  @override
  State<MatchSourceChooserDialog> createState() => _MatchSourceChooserDialogState();
}

class _MatchSourceChooserDialogState extends State<MatchSourceChooserDialog> {
  final TextEditingController _urlController = TextEditingController();

  String? errorText;
  late MatchSource source;

  @override
  void initState() {
    super.initState();
    source = widget.sources.first;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title ?? "Find a match"),
      content: SizedBox(
        width: 800,
        height: 500,
        child: Container(
          child: Column(
            mainAxisSize: MainAxisSize.max,
            children: [
              DropdownButton(
                items: widget.sources.map((e) => DropdownMenuItem(
                  child: Text(e.name),
                  value: e,
                )).toList(),
                onChanged: (s) {
                  if(s != null) {
                    setState(() {
                      source = s;
                    });
                  }
                },
                value: source,
              ),
              Divider(),
              Expanded(child: source.getDownloadMatchUI((match) {
                submit(match);
              })),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          child: Text("CANCEL"),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  void submit(ShootingMatch match) {
    Navigator.of(context).pop((source, match));
  }
}
