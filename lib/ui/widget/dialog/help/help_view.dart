/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/data/help/about.dart';
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

  final HelpIndexController _indexController = HelpIndexController();

  @override
  void initState() {
    super.initState();
    selectedTopic = HelpTopicRegistry().getTopic(widget.startingTopic)!;
  }

  @override
  void dispose() {
    _indexController.dispose();
    super.dispose();
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
            child: HelpIndex(
              controller: _indexController,
              selectedTopic: selectedTopic,
              onTopicSelected: (topic) {
                setState(() {
                  selectedTopic = topic;
                });
              },
            ),
          ),
          if(widget.twoColumn) VerticalDivider(),
          Expanded(child: HelpRenderer(topic: selectedTopic, onLinkTapped: (link) {
            if(link.startsWith("?")) {
              final topic = HelpTopicRegistry().getTopic(link.substring(1));
              if(topic != null) {
                setState(() {
                  selectedTopic = topic;
                });
                var index = HelpTopicRegistry().alphabeticalIndex(topic);
                _indexController.scrollToTopic(topic, index);
              }
              else {
                _log.w("Help topic $link not found");
              }
            }
            else {
              HtmlOr.openLink(link);
            }
          })),
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
  int? _scrolledIndex;

  @override
  void initState() {
    super.initState();
    if(widget.controller != null) {
      widget.controller!.addListener(_scrollToTopic);
    }
  }

  void _scrollToTopic() {
    if(_scrolledIndex != widget.controller?._scrollIndex) {
      _scrolledIndex = widget.controller?._scrollIndex;
      _scrollController.animateTo(
        _scrolledIndex! * _indexTileExtent,
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
  String? _scrollTopicId;
  int? _scrollIndex;
  void scrollToTopic(HelpTopic topic, int index) {
    _scrollTopicId = topic.id;
    _scrollIndex = index;
    notifyListeners();
  }
}