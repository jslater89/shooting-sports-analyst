import 'package:flutter/material.dart';
import 'package:uspsa_result_viewer/ui/widget/dialog/about_dialog.dart';

class EmptyScaffold extends StatelessWidget {
  final Widget? child;
  final String? title;
  final bool? operationInProgress;

  const EmptyScaffold({Key? key, this.child, this.operationInProgress = false, this.title}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    var size = MediaQuery.of(context).size;
    final primaryColor = Theme.of(context).primaryColor;
    final backgroundColor = Theme.of(context).backgroundColor;
    var animation = operationInProgress! ?
    AlwaysStoppedAnimation<Color>(backgroundColor) : AlwaysStoppedAnimation<Color>(primaryColor);

    return Scaffold(
      appBar: AppBar(
      title: Text(title ?? "USPSA Analyst"),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Icons.help),
            onPressed: () {
              showAbout(context, size);
            },
          )
        ],
        bottom: operationInProgress! ? PreferredSize(
          preferredSize: Size(double.infinity, 5),
          child: LinearProgressIndicator(value: null, backgroundColor: primaryColor, valueColor: animation),
        ) : null,
      ),
      body: Builder(
        builder: (context) {
          return child!;
        },
      ),
    );
  }

}