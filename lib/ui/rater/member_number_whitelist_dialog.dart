import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class MemberNumberWhitelistDialog extends StatefulWidget {
  const MemberNumberWhitelistDialog(this.initialList, {Key? key}) : super(key: key);

  final List<String> initialList;
  
  @override
  State<MemberNumberWhitelistDialog> createState() => _MemberNumberWhitelistDialogState();
}

class _MemberNumberWhitelistDialogState extends State<MemberNumberWhitelistDialog> {
  TextEditingController nameController = TextEditingController();

  @override
  void initState() {
    super.initState();

    nameController.text = widget.initialList.join("\n");
  }

  String _errorText = "";
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("Whitelist Members"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: 600),
          Text("Enter only the numeric part of member numbers, one per line."),
          Text(_errorText, style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: Theme.of(context).errorColor)),
          Expanded(
            child: SingleChildScrollView(
              child: TextField(
                keyboardType: TextInputType.multiline,
                maxLines: null,
                decoration: InputDecoration(
                  hintText: "102675..."
                ),
                controller: nameController,
                inputFormatters: [
                  FilteringTextInputFormatter(RegExp(r"[0-9\n]"), allow: true)
                ],
              ),
            ),
          )
        ],
      ),
      actions: [
        TextButton(
          child: Text("CANCEL"),
          onPressed: () {
            Navigator.of(context).pop(<String>[]);
          },
        ),
        TextButton(
          child: Text("OK"),
          onPressed: () {
            var text = nameController.text.replaceAll("\r","");
            List<String> numbers = text.split("\n").map((url) => url.trim()).toList();
            Navigator.of(context).pop(numbers);
          },
        )
      ],
    );
  }
}
