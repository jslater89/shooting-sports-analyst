/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

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
        Text(captionText!, style: Theme.of(context).textTheme.bodySmall),
        Text(text!),
      ],
    );
  }

}
