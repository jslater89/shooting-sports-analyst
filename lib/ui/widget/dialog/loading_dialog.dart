import 'package:flutter/material.dart';

class LoadingDialog<T> extends StatefulWidget {
  const LoadingDialog({Key? key, this.title = "Loading...", required this.waitOn}) : super(key: key);

  final String title;
  final Future<T> waitOn;

  @override
  State<LoadingDialog> createState() => _LoadingDialogState<T>();
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
        height: 32,
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