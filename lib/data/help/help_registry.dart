/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/data/help/help_directory.dart';
import 'package:shooting_sports_analyst/logger.dart';

SSALogger _log = SSALogger("HelpTopicRegistry");

/// A top level registry for all help topics, allowing searching and
/// cross-directory linking.
class HelpTopicRegistry {
  static late final HelpTopicRegistry _instance;
  factory HelpTopicRegistry() => _instance;

  HelpTopicRegistry.create(this._root) {
    _instance = this;
  }

  final HelpDirectory _root;

  void reload() {
    _root.reload();
  }

  HelpRegistryEntry? getTopic(String id) {
    return _root.getTopic(id);
  }
}

abstract class HelpRegistryEntry {
  String get id;
  String get name;
  HelpDirectory? get parent;
  set parent(HelpDirectory? value);

  bool get hasContent;
  String contentPreview();
}
