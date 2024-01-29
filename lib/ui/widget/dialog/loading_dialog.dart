/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ProgressModel extends ChangeNotifier {
  int _current = 0;
  int get current => _current;
  set current(int value) {
    _current = value;
    notifyListeners();
  }

  int total = 1;
  double get ratio => current / total;
}

class LoadingDialog<T> extends StatefulWidget {
  const LoadingDialog({Key? key, this.title = "Loading...", required this.waitOn}) : super(key: key);

  final String title;
  final Future<T> waitOn;

  @override
  State<LoadingDialog> createState() => _LoadingDialogState<T>();

  static Future<T> show<T>({required BuildContext context, required Future<T> waitOn, String title = "Loading...", ProgressModel? progressProvider}) async {
    var result = await showDialog(context: context, barrierDismissible: false, builder: (context) {
      if(progressProvider != null) {
        return ChangeNotifierProvider.value(
          value: progressProvider,
          builder: (context, _) => LoadingDialog(title: title, waitOn: waitOn),
        );
      }
      else {
        return LoadingDialog(title: title, waitOn: waitOn);
      }
    });

    return result;
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
    var provider = context.watch<ProgressModel?>();
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        height: 64,
        width: 64,
        child: Column(
          children: [
            if(provider != null)
              Text("${provider.current} / ${provider.total}"),
            if(provider != null)
              SizedBox(height: 10),
            CircularProgressIndicator(
              value: provider?.ratio,
            ),
          ],
        ),
      )
    );
  }
}
