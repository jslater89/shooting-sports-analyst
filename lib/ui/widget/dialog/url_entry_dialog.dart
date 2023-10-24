/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';

class UrlEntryDialog extends StatefulWidget {
  const UrlEntryDialog({Key? key, required this.hintText, this.title, this.descriptionText, this.validator}) : super(key: key);

  final String? title;
  final String? descriptionText;
  final String hintText;
  final String? Function(String)? validator;

  @override
  State<UrlEntryDialog> createState() => _UrlEntryDialogState();
}

class _UrlEntryDialogState extends State<UrlEntryDialog> {
  final TextEditingController _urlController = TextEditingController();

  String? errorText;

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
                hintText: widget.hintText,
                errorText: errorText,
              ),
              controller: _urlController,
              onFieldSubmitted: (text) {
                var url = _urlController.text;
                var error = widget.validator?.call(url);

                setState(() {
                  errorText = error;
                });
                if(error == null) Navigator.of(context).pop(url);
              },
            ),
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
              if(error == null) Navigator.of(context).pop(url);
            }
        )
      ],
    );
  }
}
