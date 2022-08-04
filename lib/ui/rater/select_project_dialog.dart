import 'package:flutter/material.dart';
import 'package:uspsa_result_viewer/data/ranking/project_manager.dart';

class SelectProjectDialog extends StatelessWidget {
  const SelectProjectDialog({Key? key, required this.projectNames}) : super(key: key);

  final List<String> projectNames;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("Select Project"),
      content: SizedBox(
        width: 600,
        child: ListView.builder(
          shrinkWrap: true,
          itemBuilder: (context, i) {
            var name = projectNames[i];
            return ListTile(
              title: Text(name),
              onTap: () {
                Navigator.of(context).pop(name);
              },
            );
          },
          itemCount: projectNames.length,
        ),
      ),
    );
  }
}
