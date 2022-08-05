import 'package:flutter/material.dart';
import 'package:uspsa_result_viewer/data/ranking/project_manager.dart';
import 'package:uspsa_result_viewer/ui/confirm_dialog.dart';

class SelectProjectDialog extends StatefulWidget {
  const SelectProjectDialog({Key? key, required this.projectNames}) : super(key: key);

  final List<String> projectNames;

  @override
  State<SelectProjectDialog> createState() => _SelectProjectDialogState();
}

class _SelectProjectDialogState extends State<SelectProjectDialog> {
  List<String> _localNames = [];
  @override
  void initState() {
    super.initState();
    _localNames = widget.projectNames;
  }
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("Select Project"),
      content: SizedBox(
        width: 600,
        child: ListView.builder(
          shrinkWrap: true,
          itemBuilder: (context, i) {
            var name = _localNames[i];
            return ListTile(
              title: Text(name),
              trailing: IconButton(
                icon: Icon(Icons.delete),
                onPressed: () async {
                  var delete = await showDialog<bool>(context: context, builder: (context) {
                    return ConfirmDialog();
                  });

                  if(delete ?? false) {
                    RatingProjectManager().deleteProject(name);
                    setState(() {
                      _localNames.remove(name);
                    });
                  }
                },
              ),
              onTap: () {
                Navigator.of(context).pop(name);
              },
            );
          },
          itemCount: _localNames.length,
        ),
      ),
    );
  }
}
