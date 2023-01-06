import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:uspsa_result_viewer/data/ranking/rater.dart';

class MemberNumberDialog extends StatefulWidget {
  const MemberNumberDialog({
    Key? key,
    this.initialList = const [],
    required this.title,
    this.helpText,
    this.hintText,
    this.width = 600,
  }) : super(key: key);

  final List<String> initialList;
  final String title;
  final String? helpText;
  final String? hintText;
  final double width;

  @override
  State<MemberNumberDialog> createState() => _MemberNumberDialogState();
}

class _MemberNumberDialogState extends State<MemberNumberDialog> {
  List<String> numbers = [];
  String errorText = "";
  
  var inputController = TextEditingController();
  
  @override
  void initState() {
    super.initState();

    numbers.addAll(widget.initialList);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      scrollable: true,
      content: SizedBox(
        width: widget.width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if(widget.helpText != null) Text(widget.helpText!),
            Text(errorText, style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: Theme.of(context).errorColor)),
            SizedBox(
              width: widget.width / 2,
              child: TextField(
                controller: inputController,
                decoration: InputDecoration(
                  hintText: widget.hintText,
                  suffix: IconButton(
                    icon: Icon(Icons.add),
                    onPressed: () {
                      submit(inputController.text);
                    },
                  )
                ),
                onSubmitted: (input) {
                  submit(input);
                },
              ),
            ),
            SizedBox(height: 8),
            for(var number in numbers) SizedBox(
              width: widget.width / 3,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                mainAxisSize: MainAxisSize.max,
                children: [
                  Text(number),
                  SizedBox(width: 10),
                  IconButton(
                    icon: Icon(Icons.remove),
                    onPressed: () {
                      setState(() {
                        numbers.remove(number);
                      });
                    },
                  )
                ],
              ),
            )
          ],
        ),
      ),
      actions: [
        TextButton(
          child: Text("CANCEL"),
          onPressed: () {
            Navigator.of(context).pop(null);
          },
        ),
        TextButton(
          child: Text("OK"),
          onPressed: () {
            Navigator.of(context).pop(numbers);
          },
        )
      ],
    );
  }

  void submit(String input) {
    if(!input.contains(RegExp(r"[0-9]+"))) {
      setState(() {
        errorText = "Member number must contain at least one number.";
      });
      return;
    }
    else if(numbers.contains(input)) {
      setState(() {
        errorText = "List already contains that number.";
      });
      return;
    }
    else {
      setState(() {
        errorText = "";
      });
    }

    setState(() {
      numbers.add(Rater.processMemberNumber(input));
      inputController.clear();
    });
  }
}
