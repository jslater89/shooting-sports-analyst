import 'package:flutter/material.dart';
import 'package:uspsa_result_viewer/data/ranking/project_manager.dart';

class EnterNameDialog extends StatefulWidget {
  const EnterNameDialog({Key? key, this.initial}) : super(key: key);

  final String? initial;

  @override
  State<EnterNameDialog> createState() => _EnterNameDialogState();
}

class _EnterNameDialogState extends State<EnterNameDialog> {
  late TextEditingController nameController;
  String _errorText = "";
  bool confirm = false;
  bool confirmed = false;
  
  @override
  void initState() {
    super.initState();

    nameController = TextEditingController(text: widget.initial);
    nameController.addListener(() { 
      if(RatingProjectManager().projectExists(nameController.text)) {
        setState(() {
          confirm = true;
          _errorText = "A project with that name exists. Tap 'OK' twice to confirm overwrite.";
        });
      }
      else {
        setState(() {
          confirm = false;
          confirmed = false;
          _errorText = "";
        });
      }
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("Set Project Name"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: 400),
          Text(_errorText, style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: Theme.of(context).errorColor)),
          TextField(
            keyboardType: TextInputType.text,
            decoration: InputDecoration(
              hintText: "Project Name"
            ),
            controller: nameController,
          )
        ],
      ),
      actions: [
        TextButton(
          child: Text("CANCEL"),
          onPressed: () {
            Navigator.of(context).pop("");
          },
        ),
        TextButton(
          child: Text("OK"),
          onPressed: () {
            if(nameController.text.length == 0) {
              setState(() {
                _errorText = "String is empty";
              });
            }

            if(confirm && confirmed) {
              Navigator.of(context).pop(nameController.text);
              debugPrint("Saving");
            }
            else if(confirm && !confirmed) {
              confirmed = true;
              setState(() {
                _errorText = "Tap again to confirm.";
              });
              debugPrint("Confirm requested");
            }
            else {
              Navigator.of(context).pop(nameController.text);
              debugPrint("Confirm not needed");
            }
          },
        )
      ],
    );
  }
}