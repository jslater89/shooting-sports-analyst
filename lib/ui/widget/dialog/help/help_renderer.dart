/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/help/help_topic.dart';

const _shouldCacheRenderedSpans = !kDebugMode;

class HelpRenderer extends StatefulWidget {
  const HelpRenderer({
    super.key,
    required this.topic,
    required this.onLinkTapped,
  });

  final HelpTopic topic;
  final void Function(String id) onLinkTapped;

  @override
  State<HelpRenderer> createState() => _HelpRendererState();
}

class _HelpRendererState extends State<HelpRenderer> {
  final Map<String, List<InlineSpan>> _contentCache = {};

  @override
  Widget build(BuildContext context) {
    var tokens = widget.topic.tokenize();
    List<InlineSpan> spans;
    if(_shouldCacheRenderedSpans && _contentCache[widget.topic.id] != null) {
      spans = _contentCache[widget.topic.id]!;
    }
    else {
      spans = tokens.map((e) => e.intoSpans(context, Theme.of(context).textTheme.bodyMedium!, onLinkTapped: widget.onLinkTapped)).flattened.toList();
      _contentCache[widget.topic.id] = spans;
    }
    return SingleChildScrollView(
      child: RichText(
        text: TextSpan(
          children: spans,
        ),
      ),
    );
  }
}