/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';

class LoadingDialog<T> extends StatefulWidget {
  const LoadingDialog({Key? key, this.title = "Loading...", required this.waitOn}) : super(key: key);

  final String title;
  final Future<T> waitOn;

  @override
  State<LoadingDialog> createState() => _LoadingDialogState<T>();

  static Future<T> show<T>({required BuildContext context, required Future<T> waitOn, String title = "Loading..."}) async {
    var result = await showDialog(context: context, barrierDismissible: false, builder: (context) =>
      LoadingDialog(title: title, waitOn: waitOn)
    );

    return result!;
  }
}

class _LoadingDialogState<T> extends State<LoadingDialog> {
  @override
  void initState() {
    super.initState();

    _wait();
  }

  void _wait() async {
    T result = await widget.waitOn;
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        height: 48,
        width: 32,
        child: Center(
          child: CircularProgressIndicator(
            value: null,
          ),
        ),
      )
    );
  }
}
