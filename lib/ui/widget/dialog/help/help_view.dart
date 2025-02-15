/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/data/help/about_help.dart';
import 'package:shooting_sports_analyst/html_or/html_or.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/help/help_registry.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/help/help_renderer.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/help/help_topic.dart';

SSALogger _log = SSALogger("HelpView");

class HelpView extends StatefulWidget {
  const HelpView({super.key, this.startingTopic = aboutHelpId, this.twoColumn = true, this.width = 1000});

  final double width;
  final bool twoColumn;
  final String startingTopic;

  @override
  State<HelpView> createState() => _HelpViewState();
}

class _HelpViewState extends State<HelpView> {
  late HelpTopic selectedTopic;

  int backStackIndex = 0;
  List<HelpTopic> backStack = [];

  final HelpIndexController _indexController = HelpIndexController();
  final HelpRendererController _rendererController = HelpRendererController();
  @override
  void initState() {
    super.initState();
    selectedTopic = HelpTopicRegistry().getTopic(widget.startingTopic)!;
    backStack.add(selectedTopic);
  }

  @override
  void dispose() {
    _indexController.dispose();
    _rendererController.dispose();
    super.dispose();
  }

  /// When navigating by link, the new topic gets pushed onto the back stack,
  /// and any topics above it in the stack are removed—i.e., going back and then
  /// forward will go to [topic] rather than the previous topic.
  void navigateByLink(HelpTopic topic) {
    if(backStackIndex < backStack.length - 1) {
      backStack.removeRange(backStackIndex + 1, backStack.length);
    }
    backStack.add(topic);
    backStackIndex++;

    setTopic(topic);
  }

  void setTopic(HelpTopic topic) {
    setState(() {
      selectedTopic = topic;
    });

    _indexController.scrollToTopic(topic);
    _rendererController.scrollToTop();
  }

  bool get canNavigateBack => backStackIndex > 0;

  void navigateBack() {
    if(backStackIndex > 0) {
      backStackIndex--;
      setTopic(backStack[backStackIndex]);
    }
  }

  bool get canNavigateForward => backStackIndex < backStack.length - 1;

  void navigateForward() {
    if(backStackIndex < backStack.length - 1) {
      backStackIndex++;
      setTopic(backStack[backStackIndex]);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if(widget.twoColumn) SizedBox(
            width: 300,
            child: Column(
              children: [
                Row(
                  mainAxisSize: MainAxisSize.max,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back),
                      onPressed: canNavigateBack ? navigateBack : null,
                    ),
                    IconButton(
                      icon: Icon(Icons.arrow_forward),
                      onPressed: canNavigateForward ? navigateForward : null,
                    ),
                  ],
                ),
                Expanded(
                  child: HelpIndex(
                    controller: _indexController,
                    selectedTopic: selectedTopic,
                    onTopicSelected: (topic) {
                      navigateByLink(topic);
                    },
                  ),
                ),
              ],
            ),
          ),
          if(widget.twoColumn) VerticalDivider(),
          Expanded(
            child: HelpRenderer(
              topic: selectedTopic,
              controller: _rendererController,
              onLinkTapped: (link) {
                if(link.startsWith("?")) {
                  final topic = HelpTopicRegistry().getTopic(link.substring(1));
                  if(topic != null) {
                    navigateByLink(topic);
                  }
                  else {
                    _log.w("Help topic $link not found");
                  }
                }
                else {
                  HtmlOr.openLink(link);
                }
              }
            )
          ),
        ]
      )
    );
  }
}

class HelpIndex extends StatefulWidget {
  const HelpIndex({super.key, required this.selectedTopic, required this.onTopicSelected, this.controller});

  final HelpTopic selectedTopic;
  final void Function(HelpTopic topic) onTopicSelected;
  final HelpIndexController? controller;

  @override
  State<HelpIndex> createState() => _HelpIndexState();
}

class _HelpIndexState extends State<HelpIndex> {
  static const _indexTileExtent = 65.0;

  final ScrollController _scrollController = ScrollController();
  HelpTopic? _scrolledTopic;

  @override
  void initState() {
    super.initState();
    if(widget.controller != null) {
      widget.controller!.addListener(_scrollToTopic);
    }
  }

  void _scrollToTopic() {
    var targetTopic = widget.controller?._scrollTopic;
    if(targetTopic != null && targetTopic != _scrolledTopic) {
      _scrolledTopic = targetTopic;
      var index = HelpTopicRegistry().alphabeticalIndex(targetTopic);
      _scrollController.animateTo(
        index * _indexTileExtent,
        duration: Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Widget build(BuildContext context) {
    return ListView.builder(
      controller: _scrollController,
      itemBuilder: (context, index) {
        final topic = HelpTopicRegistry().alphabetical(index);
        return SizedBox(
          height: _indexTileExtent,
          child: ListTile(
            title: Text(topic.name),
            subtitle: Text(topic.contentPreview(), softWrap: false, overflow: TextOverflow.ellipsis),
            onTap: () => widget.onTopicSelected(topic),
            selected: topic.id == widget.selectedTopic.id,
          ),
        );
      },
      itemCount: HelpTopicRegistry().length,
    );
  }
}

class HelpIndexController with ChangeNotifier {
  HelpTopic? _scrollTopic;
  void scrollToTopic(HelpTopic topic) {
    _scrollTopic = topic;
    notifyListeners();
  }
}