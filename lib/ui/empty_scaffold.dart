import 'package:flutter/material.dart';
import 'package:uspsa_result_viewer/ui/about_dialog.dart';

class EmptyScaffold extends StatelessWidget {
  final Widget? child;
  final bool? operationInProgress;
  final Function(BuildContext) onInnerContextAssigned;

  const EmptyScaffold({Key? key, this.child, this.operationInProgress, required this.onInnerContextAssigned}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    var size = MediaQuery.of(context).size;
    final primaryColor = Theme.of(context).primaryColor;
    final backgroundColor = Theme.of(context).backgroundColor;
    var animation = operationInProgress! ?
    AlwaysStoppedAnimation<Color>(backgroundColor) : AlwaysStoppedAnimation<Color>(primaryColor);

    return Scaffold(
      appBar: AppBar(
      title: Text("Match Results Viewer"),
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
          onInnerContextAssigned(context);
          return child!;
        },
      ),
    );
  }

}