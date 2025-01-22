/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';

class ConfirmDialog extends StatelessWidget {
  const ConfirmDialog({Key? key, this.content, this.title, this.positiveButtonLabel, this.negativeButtonLabel, this.width}) : super(key: key);

  final Widget? content;
  final String? title;
  final String? positiveButtonLabel;
  final String? negativeButtonLabel;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title ?? "Are you sure?"),
      content: SizedBox(width: width, child: content),
      actions: [
        TextButton(
          child: Text(negativeButtonLabel ?? "CANCEL"),
          onPressed: () { Navigator.of(context).pop(false); },
        ),
        TextButton(
          child: Text(positiveButtonLabel ?? "DELETE"),
          onPressed: () { Navigator.of(context).pop(true); },
        )
      ],
    );
  }

  static Future<bool?> show(BuildContext context, {String? title, Widget? content, String? positiveButtonLabel, String? negativeButtonLabel, double? width}) async {
    return showDialog<bool>(
      context: context,
      builder: (context) => ConfirmDialog(title: title, content: content, positiveButtonLabel: positiveButtonLabel, negativeButtonLabel: negativeButtonLabel, width: width),
    );
  }
}