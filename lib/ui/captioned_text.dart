import 'package:flutter/material.dart';

class CaptionedText extends StatelessWidget {
  final String? captionText;
  final String? text;

  const CaptionedText({Key? key, this.captionText, this.text}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(captionText!, style: Theme.of(context).textTheme.caption),
        Text(text!),
      ],
    );
  }

}