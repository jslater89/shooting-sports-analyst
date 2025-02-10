import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/data/help/about.dart';
import 'package:shooting_sports_analyst/html_or/html_or.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/help/help_registry.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/help/help_renderer.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/help/help_topic.dart';

SSALogger _log = SSALogger("HelpView");

/// HelpView displays the help system in 
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

  @override
  void initState() {
    super.initState();
    selectedTopic = HelpTopicRegistry().getTopic(widget.startingTopic)!;
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

class HelpIndex extends StatelessWidget {
  const HelpIndex({super.key, required this.selectedTopic, required this.onTopicSelected});

  final HelpTopic selectedTopic;
  final void Function(HelpTopic topic) onTopicSelected;
  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemBuilder: (context, index) {
        final topic = HelpTopicRegistry().alphabetical(index);
        return ListTile(
          title: Text(topic.name),
          subtitle: Text(topic.contentPreview(), softWrap: false, overflow: TextOverflow.ellipsis),
          onTap: () => onTopicSelected(topic),
          selected: topic.id == selectedTopic.id,
        );
      },
      itemCount: HelpTopicRegistry().length,
    );
  }
}
