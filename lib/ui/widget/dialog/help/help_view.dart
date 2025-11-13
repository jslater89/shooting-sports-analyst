/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/config/config.dart';
import 'package:shooting_sports_analyst/data/help/entries/about_help.dart';
import 'package:shooting_sports_analyst/data/help/help_directory.dart';
import 'package:shooting_sports_analyst/html_or/html_or.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/data/help/help_registry.dart';
import 'package:shooting_sports_analyst/ui/colors.dart';
import 'package:shooting_sports_analyst/ui/widget/clickable_link.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/help/help_renderer.dart';

SSALogger _log = SSALogger("HelpView");

class HelpView extends StatefulWidget {
  const HelpView({super.key, this.startingTopic = aboutHelpId, this.twoColumn = true, this.width = 1000, this.scaleWidth = true});

  /// If true, the width will be scaled by the UI scale factor.
  final bool scaleWidth;
  final double width;
  final bool twoColumn;
  final String startingTopic;

  @override
  State<HelpView> createState() => _HelpViewState();
}

class _HelpViewState extends State<HelpView> {
  late HelpRegistryEntry selectedTopic;

  /// The index of the current back stack entry.
  int backStackIndex = 0;
  /// The back stack contains a list of navigation history (help ID and scroll position).
  /// The back stack contains the current topic.
  List<BackStackEntry> backStack = [];

  final HelpIndexController _indexController = HelpIndexController();
  final HelpRendererController _rendererController = HelpRendererController();
  @override
  void initState() {
    super.initState();
    selectedTopic = HelpTopicRegistry().getTopic(widget.startingTopic)!;
    backStack.add(BackStackEntry(topic: selectedTopic, scrollPosition: 0));
    _indexController.scrollToTopic(selectedTopic);
  }

  @override
  void dispose() {
    _indexController.dispose();
    _rendererController.dispose();
    super.dispose();
  }

  /// When leaving a page by link or index click, we remove all back stack entries above
  /// the currently-shown topic, update the currently-shown topic's scroll position,
  /// and push a new back stack entry for the destination topic at scroll position 0.
  void navigateByLink(HelpRegistryEntry topic) {
    // topic is our destination, and selectedTopic is the currently-displayed topic.
    if(topic.id == selectedTopic.id) {
      return;
    }

    // Remove all back stack entries above the currently-shown topic, if there are any.
    if(backStackIndex < backStack.length - 1) {
      backStack = backStack.sublist(0, backStackIndex + 1);
    }

    // Update the currently-shown topic's scroll position.
    backStack[backStackIndex].scrollPosition = _rendererController.scrollPosition;

    // Push a new back stack entry for the destination topic at scroll position 0.
    backStack.add(BackStackEntry(topic: topic, scrollPosition: 0));
    backStackIndex++;

    // Display the destination topic.
    setTopic(topic);
  }

  void setTopic(HelpRegistryEntry topic, {double rendererScrollPosition = 0}) {
    // If the topic is a directory, set the selected topic to the first topic in the directory.
    if(topic is HelpDirectory) {
      if(topic.defaultTopicId != null) {
        topic = topic.getTopic(topic.defaultTopicId!)!;
      }
      else {
        topic = topic.alphabetical(0);
      }
    }
    setState(() {
      selectedTopic = topic;
    });

    _indexController.scrollToTopic(topic);
    _rendererController.scrollToPosition(rendererScrollPosition);
  }

  bool get canNavigateBack => backStackIndex > 0;

  void navigateBack() {
    if(backStackIndex > 0) {
      backStackIndex--;
      var stackEntry = backStack[backStackIndex];
      setTopic(stackEntry.topic, rendererScrollPosition: stackEntry.scrollPosition);
      _log.v("Back navigation: back stack index is now $backStackIndex/${backStack.length - 1}");
    }
  }

  bool get canNavigateForward => backStackIndex < backStack.length - 1;

  void navigateForward() {
    if(backStackIndex < backStack.length - 1) {
      backStackIndex++;
      var stackEntry = backStack[backStackIndex];
      setTopic(stackEntry.topic, rendererScrollPosition: stackEntry.scrollPosition);
      _log.v("Forward navigation: back stack index is now $backStackIndex/${backStack.length - 1}");
    }
  }

  @override
  Widget build(BuildContext context) {
    var width = widget.width;
    if(widget.scaleWidth) {
      width = width * ChangeNotifierConfigLoader().uiConfig.uiScaleFactor;
    }
    return SizedBox(
      width: width,
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
                      color: Theme.of(context).colorScheme.primary,
                      onPressed: canNavigateBack ? navigateBack : null,
                    ),
                    IconButton(
                      icon: Icon(Icons.arrow_forward),
                      color: Theme.of(context).colorScheme.primary,
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
  final HelpRegistryEntry topic;
  double scrollPosition;

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

  @override
  String toString() {
    return "${topic.id}@$scrollPosition";
  }
}

class HelpIndex extends StatefulWidget {
  const HelpIndex({super.key, required this.selectedTopic, required this.onTopicSelected, this.controller});

  final HelpRegistryEntry selectedTopic;
  final void Function(HelpRegistryEntry topic) onTopicSelected;
  final HelpIndexController? controller;

  @override
  State<HelpIndex> createState() => _HelpIndexState();
}

class _HelpIndexState extends State<HelpIndex> {
  static const _indexTileExtent = 65.0;

  final ScrollController _scrollController = ScrollController();
  late HelpDirectory _currentDirectory;
  HelpRegistryEntry? _scrolledTopic;

  @override
  void initState() {
    super.initState();
    _currentDirectory = widget.selectedTopic.parent!;
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

  void _scrollToTopic(HelpRegistryEntry topic) {
    // If scrolling to a directory, set the current directory to the target directory
    // and scroll to the first topic in the directory.
    if(topic is HelpDirectory) {
      setState(() {
        _currentDirectory = topic;
      });
      if(topic.defaultTopicId != null) {
        _scrollToTopic(topic.getTopic(topic.defaultTopicId!)!);
      }
      else {
        _scrollToTopic(topic.alphabetical(0));
      }
      return;
    }

    setState(() {
      _currentDirectory = topic.parent!;
    });

    var index = _currentDirectory.alphabeticalIndex(topic);
    var scrollTarget = index * _indexTileExtent;
    _log.vv("Index: $index Scroll target: $scrollTarget/${_scrollController.position.maxScrollExtent}");
    _scrollController.animateTo(
      scrollTarget,
      duration: Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  Widget build(BuildContext context) {
    List<HelpDirectory> breadcrumbs = [];
    HelpDirectory? dir = _currentDirectory;
    HelpDirectory root = dir;
    while(dir != null) {
      breadcrumbs.add(dir);
      root = dir;
      dir = dir.parent;
    }
    List<Widget> breadcrumbWidgets = [];
    if(_currentDirectory.parent != null) {
      const iconSize = 20.0;
      breadcrumbWidgets = [
        ClickableLink(
          child: Icon(Icons.home, size: iconSize),
          onTap: () => widget.onTopicSelected(root),
        ),
        Icon(Icons.arrow_right_outlined, size: iconSize),
      ];
      for(var i = breadcrumbs.length - 1; i >= 0; i--) {
        var dir = breadcrumbs[i];
        breadcrumbWidgets.add(ClickableLink(
          child: Text(dir.name, style: Theme.of(context).textTheme.bodyMedium),
          onTap: () => widget.onTopicSelected(dir),
        ));
        // first arrow comes from the 'home' icon
        if(i > 1) {
          breadcrumbWidgets.add(Icon(Icons.arrow_right_outlined, size: iconSize));
        }
      }
    }
    return Column(
      children: [
        if(breadcrumbWidgets.isNotEmpty) Container(
          padding: const EdgeInsets.only(bottom: 4.0),
          child: Row(
            children: breadcrumbWidgets,
          ),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: ThemeColors.onBackgroundColor(context),
              ),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            itemBuilder: (context, index) {
              final topic = _currentDirectory.alphabetical(index);
              return SizedBox(
                height: _indexTileExtent,
                child: ListTile(
                  leading: topic is HelpDirectory ? Icon(Icons.folder_outlined) : null,
                  title: Text(topic.name),
                  subtitle: Text(topic.contentPreview(), softWrap: false, overflow: TextOverflow.ellipsis),
                  onTap: () => widget.onTopicSelected(topic),
                  selected: topic.id == widget.selectedTopic.id,
                ),
              );
            },
            itemCount: _currentDirectory.length,
          ),
        ),
      ],
    );
  }
}

class HelpIndexController with ChangeNotifier {
  HelpRegistryEntry? _scrollTopic;
  void scrollToTopic(HelpRegistryEntry topic) {
    _scrollTopic = topic;
    notifyListeners();
  }
}
