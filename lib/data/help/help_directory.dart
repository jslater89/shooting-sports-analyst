/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/data/help/help_registry.dart';

/// A help index is a directory of help topics that can be organized in
/// a hierarchy. A directory can contain other directories, as well
/// as help topics.
class HelpDirectory extends HelpRegistryEntry {
  final String id;
  final String name;
  final String? defaultTopicId;
  HelpDirectory? parent;
  List<HelpRegistryEntry> _children = [];
  List<HelpRegistryEntry> _alphabetizedChildren = [];
  Map<String, HelpRegistryEntry> _childrenById = {};
  Map<HelpRegistryEntry, int> _alphabeticalIndexes = {};

  void addChild(HelpRegistryEntry child) {
    child.parent = this;
    _children.add(child);
    _childrenById[child.id] = child;
    _alphabetizedChildren.add(child);
    _alphabetizedChildren.sort((a, b) => a.name.compareTo(b.name));
    for(int i = 0; i < _alphabetizedChildren.length; i++) {
      _alphabeticalIndexes[_alphabetizedChildren[i]] = i;
    }
  }

  HelpRegistryEntry? getTopic(String id) {
    var foundEntry = _childrenById[id];
    if(foundEntry != null) {
      return foundEntry;
    }
    for(var directory in _children.whereType<HelpDirectory>()) {
      var found = directory.getTopic(id);
      if(found != null) {
        return found;
      }
    }
    return null;
  }

  int get length => _children.length;

  List<HelpRegistryEntry> get topics => _alphabetizedChildren;

  HelpRegistryEntry alphabetical(int index) {
    return _alphabetizedChildren[index];
  }

  int alphabeticalIndex(HelpRegistryEntry entry) {
    return _alphabeticalIndexes[entry]!;
  }

   void initialize() {
    _alphabetizedChildren.clear();
    _alphabeticalIndexes.clear();
    _childrenById.clear();
  }

  void reload() {
    initialize();
    var childrenCopy = [..._children];
    _children.clear();
    for(var child in childrenCopy) {
      addChild(child);
    }
  }

  String contentPreview() {
    return "(${_children.length} topics)";
  }

  HelpDirectory({required this.id, required this.name, this.parent, this.defaultTopicId});

  bool get hasContent => false;
}
