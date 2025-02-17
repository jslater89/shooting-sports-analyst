/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/help/help_topic.dart';

SSALogger _log = SSALogger("HelpTopicRegistry");

class HelpTopicRegistry {
  static final HelpTopicRegistry _instance = HelpTopicRegistry._();
  factory HelpTopicRegistry() => _instance;

  HelpTopicRegistry._();

  final Map<String, HelpTopic> _topics = {};
  List<HelpTopic> _alphabetizedTopics = [];
  Map<HelpTopic, int> _alphabeticalIndexes = {};

  void register(HelpTopic topic) {
    _log.v("Registered topic: ${topic.id}");
    _topics[topic.id] = topic;
    _alphabetizedTopics.add(topic);
    _alphabetizedTopics.sort((a, b) => a.name.compareTo(b.name));
    for(int i = 0; i < _alphabetizedTopics.length; i++) {
      _alphabeticalIndexes[_alphabetizedTopics[i]] = i;
    }
  }

  HelpTopic? getTopic(String id) {
    return _topics[id];
  }

  int get length => _topics.length;

  List<HelpTopic> get topics => _alphabetizedTopics;

  HelpTopic alphabetical(int index) {
    return _alphabetizedTopics[index];
  }

  int alphabeticalIndex(HelpTopic topic) {
    return _alphabeticalIndexes[topic]!;
  }

  void initialize() {
    _alphabetizedTopics.clear();
    _alphabeticalIndexes.clear();
  }

  void reload() {
    initialize();
    for(var topic in _topics.values) {
      register(topic);
    }
  }
}