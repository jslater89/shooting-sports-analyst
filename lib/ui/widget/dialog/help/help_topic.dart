/// A help topic is an article that can be displayed to the user.
/// 
/// It can be formatted with a very small subset of Markdown,
/// including # and ## headers, _italics_, *bold*, and
/// [links](#help-topic-id).
class HelpTopic {
  final String id;
  final String name;
  final String content;

  HelpTopic({
    required this.id,
    required this.name,
    required this.content,
  });
}

class HelpTopicRegistry {
  final Map<String, HelpTopic> _topics = {};

  void register(HelpTopic topic) {
    _topics[topic.id] = topic;
  }

  HelpTopic? getTopic(String id) {
    return _topics[id];
  }
}