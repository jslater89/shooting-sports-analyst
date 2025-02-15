/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/help/help_parser.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/help/help_topic.dart';

const _shouldCacheRenderedSpans = !kDebugMode;

class HelpRenderer extends StatefulWidget {
  const HelpRenderer({
    super.key,
    required this.topic,
    required this.onLinkTapped,
    this.controller,
  });

  final HelpTopic topic;
  final void Function(String id) onLinkTapped;
  final HelpRendererController? controller;
  @override
  State<HelpRenderer> createState() => _HelpRendererState();
}

class _HelpRendererState extends State<HelpRenderer> {
  final Map<String, List<InlineSpan>> _contentCache = {};

  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_handleControllerNotify);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _handleControllerNotify() async {
    var controller = widget.controller!;
    if(controller._shouldScrollToTop && !controller._isScrolling) {
      controller._isScrolling = true;
      await _scrollToTop();
      controller._isScrolling = false;
      controller._shouldScrollToTop = false;
    }
  }

  Future<void> _scrollToTop() async {
    await Future.delayed(Duration(milliseconds: 300));
    _scrollController.animateTo(
      0,
      duration: Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    var tokens = HelpParser.tokenize(widget.topic);
    List<InlineSpan> spans;
    if(_shouldCacheRenderedSpans && _contentCache[widget.topic.id] != null) {
      spans = _contentCache[widget.topic.id]!;
    }
    else {
      spans = tokens.map((e) => e.intoSpans(context, Theme.of(context).textTheme.bodyMedium!, onLinkTapped: widget.onLinkTapped)).flattened.toList();
      _contentCache[widget.topic.id] = spans;
    }
    return SingleChildScrollView(
      controller: _scrollController,
      child: RichText(
        text: TextSpan(
          children: spans,
        ),
      ),
    );
  }
}

class HelpRendererController extends ChangeNotifier {
  bool _shouldScrollToTop = false;
  bool _isScrolling = false;

  void scrollToTop() {
    _shouldScrollToTop = true;
    notifyListeners();
  }
}