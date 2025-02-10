import 'package:shooting_sports_analyst/data/help/about.dart';
import 'package:shooting_sports_analyst/data/help/deduplication_help.dart';
import 'package:shooting_sports_analyst/data/help/elo_help.dart';
import 'package:shooting_sports_analyst/data/help/openskill_help.dart';
import 'package:shooting_sports_analyst/data/help/points_help.dart';
import 'package:shooting_sports_analyst/data/help/rating_event.dart';
import 'package:shooting_sports_analyst/data/help/uspsa_deduplicator_help.dart';
import 'package:shooting_sports_analyst/data/help/elo_configuration_help.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/help/help_topic.dart';

SSALogger _log = SSALogger("HelpTopicRegistry");

class HelpTopicRegistry {
  static final HelpTopicRegistry _instance = HelpTopicRegistry._();
  factory HelpTopicRegistry() => _instance;

  HelpTopicRegistry._();

  final Map<String, HelpTopic> _topics = {};
  List<HelpTopic> _alphabetizedTopics = [];

  void register(HelpTopic topic) {
    _log.v("Registered topic: ${topic.id}");
    _topics[topic.id] = topic;
    _alphabetizedTopics.add(topic);
    _alphabetizedTopics.sort((a, b) => a.name.compareTo(b.name));
  }

  HelpTopic? getTopic(String id) {
    return _topics[id];
  }

  int get length => _topics.length;

  List<HelpTopic> get topics => _alphabetizedTopics;

  HelpTopic alphabetical(int index) {
    return _alphabetizedTopics[index];
  }

  void initialize() {
    _alphabetizedTopics.clear();
    register(helpAbout);
    register(helpUspsaDeduplicator);
    register(helpDeduplication);
    register(helpEloConfig);
    register(helpElo);
    register(helpOpenSkill);
    register(helpPoints);
    register(helpRatingEvent);
  }
}