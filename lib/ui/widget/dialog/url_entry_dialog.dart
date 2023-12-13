/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:uspsa_result_viewer/data/source/registered_sources.dart';
import 'package:uspsa_result_viewer/data/source/source.dart';

class UrlEntryDialog extends StatefulWidget {
  const UrlEntryDialog({Key? key, this.hintText, this.sources, this.title, this.descriptionText, this.validator}) : super(key: key);

  /// The title for the URL entry dialog.
  final String? title;
  /// The description text to show in the URL dialog, above the entry dialog.
  final String? descriptionText;
  /// The hint text to show in the URL dialog.
  final String? hintText;
  /// If present, show a dropdown list of match sources below the URL entry
  /// dialog, and return a tuple of (MatchSource, String?) instead of a string.
  final List<MatchSource>? sources;
  final String? Function(String)? validator;

  @override
  State<UrlEntryDialog> createState() => _UrlEntryDialogState();
}

class _UrlEntryDialogState extends State<UrlEntryDialog> {
  final TextEditingController _urlController = TextEditingController();

  String? errorText;
  MatchSource? source;

  @override
  void initState() {
    super.initState();
    if(widget.sources != null) {
      source = widget.sources!.first;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title ?? "Enter match link"),
      content: Container(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.descriptionText ?? "Enter a link to a match."),
            TextFormField(
              decoration: InputDecoration(
                hintText: widget.hintText ?? "https://practiscore.com/results/new/...",
                errorText: errorText,
              ),
              controller: _urlController,
              onFieldSubmitted: (text) {
                var url = _urlController.text;
                var error = widget.validator?.call(url);

                setState(() {
                  errorText = error;
                });
                if(error == null) submit(url);
              },
            ),
            if(widget.sources != null)
              DropdownButton<MatchSource>(
                items: widget.sources!.map((e) =>
                    DropdownMenuItem<MatchSource>(
                      child: Text(e.name),
                      value: e,
                    )
                ).toList(),
                value: source!,
                onChanged: (v) {
                  setState(() {
                    source = v;
                  });
                },
              )
          ],
        ),
      ),
      actions: [
        TextButton(
          child: Text("CANCEL"),
          onPressed: () => Navigator.of(context).pop(),
        ),
        TextButton(
            child: Text("OK"),
            onPressed: () {
              var url = _urlController.text;
              var error = widget.validator?.call(url);

              setState(() {
                errorText = error;
              });
              if(error == null) submit(url);
            }
        )
      ],
    );
  }

  void submit(String url) {
    if(widget.sources == null) {
      Navigator.of(context).pop(url);
    }
    else {
      Navigator.of(context).pop((source, url));
    }
  }
}
