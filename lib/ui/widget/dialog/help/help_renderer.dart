/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/help/help_topic.dart';

class HelpRenderer extends StatelessWidget {
  const HelpRenderer({
    super.key,
    required this.topic,
    required this.onLinkTapped,
  });

  final HelpTopic topic;
  final void Function(String id) onLinkTapped;

  @override
  Widget build(BuildContext context) {
    var tokens = topic.tokenize();
    var spans = tokens.map((e) => e.intoSpans(context, Theme.of(context).textTheme.bodyMedium!, onLinkTapped: onLinkTapped)).flattened.toList();
    return SingleChildScrollView(
      child: RichText(
        text: TextSpan(
          children: spans,
        ),
      ),
    );
  }
}