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
  List<BackStackEntry> backStack = [];

  final HelpIndexController _indexController = HelpIndexController();
  final HelpRendererController _rendererController = HelpRendererController();
  @override
  void initState() {
    super.initState();
    selectedTopic = HelpTopicRegistry().getTopic(widget.startingTopic)!;
    backStack.add(BackStackEntry(topic: selectedTopic));
    _indexController.scrollToTopic(selectedTopic);
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
    if(topic.id == selectedTopic.id) {
      return;
    }
    // When leaving a page, add a new back stack entry for it with the current scroll position,
    _log.d("Adding back stack entry for topic ${selectedTopic.id} at scroll position ${_rendererController.scrollPosition}");
    backStack.add(BackStackEntry(topic: selectedTopic, scrollPosition: _rendererController.scrollPosition));
    backStackIndex++;

    setTopic(topic);
  }

  void setTopic(HelpTopic topic, {double rendererScrollPosition = 0}) {
    setState(() {
      selectedTopic = topic;
    });

    _indexController.scrollToTopic(topic);
    _rendererController.scrollToPosition(rendererScrollPosition);
  }

  bool get canNavigateBack => backStackIndex > 0;

  void navigateBack() {
    if(backStackIndex > 0) {
      var stackEntry = backStack[backStackIndex];
      setTopic(stackEntry.topic, rendererScrollPosition: stackEntry.scrollPosition);
      backStackIndex--;
    }
  }

  bool get canNavigateForward => backStackIndex < backStack.length - 1;

  void navigateForward() {
    if(backStackIndex < backStack.length - 1) {
      var stackEntry = backStack[backStackIndex];
      setTopic(stackEntry.topic, rendererScrollPosition: stackEntry.scrollPosition);
      backStackIndex++;
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

class BackStackEntry {
  final HelpTopic topic;
  final double scrollPosition;

  BackStackEntry({required this.topic, this.scrollPosition = 0});

  @override
  bool operator ==(Object other) {
    if(other is BackStackEntry) {
      return topic.id == other.topic.id;
    }
    return false;
  }

  @override
  int get hashCode => topic.id.hashCode;
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
      widget.controller!.addListener(_handleControllerNotification);
    }

    // Scroll to initial topic after build
    Future.delayed(Duration.zero, () {
      _scrollToTopic(widget.selectedTopic);
    });
  }

  void _handleControllerNotification() {
    var targetTopic = widget.controller?._scrollTopic;
    if(targetTopic != null && targetTopic != _scrolledTopic) {
      _scrolledTopic = targetTopic;
      _scrollToTopic(targetTopic);
    }
  }

  void _scrollToTopic(HelpTopic topic) {
    var index = HelpTopicRegistry().alphabeticalIndex(topic);
    var scrollTarget = index * _indexTileExtent;
    _log.vv("Index: $index Scroll target: $scrollTarget/${_scrollController.position.maxScrollExtent}");
    _scrollController.animateTo(
      scrollTarget,
      duration: Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
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