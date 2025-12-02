/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:isar_community/isar.dart';

extension LinkUtilities<T> on IsarLinks<T> {
  void empty({bool ensureLoaded = false}) {
    if(ensureLoaded && !isLoaded) {
      load();
    }
    var temp = [...this];
    for(var item in temp) {
      remove(item);
    }
  }

  /// Sets the contents of the links object to the given [newContents]
  /// with an immediate DB call.
  Future<void> setContentsTo(Isar isar, Iterable<T> newContents) {
    return isar.writeTxn(() async {
      await update(reset: true, link: newContents);
    });
  }

  /// Sets the contents of the links object to the given [newContents]
  /// without an immediate DB call.
  void setContentsToSync(Isar isar,Iterable<T> newContents) {
    isar.writeTxnSync(() {
      updateSync(reset: true, link: newContents);
    });
  }

  /// Applies the given [change] to the links object. This is
  /// not a DB call, and the change will not be persisted until
  /// the next call to [save].
  void apply(IsarLinksChange<T> change) {
    for(var item in change.added) {
      add(item);
    }
    for(var item in change.removed) {
      remove(item);
    }
  }
}

/// Information necessary to update an IsarLinks object.
///
/// [currentSelection] is the current selection of items in the links object.
/// [added] is the list of items that were added to the links object.
/// [removed] is the list of items that were removed from the links object.
class IsarLinksChange<T> {
  final List<T> startingSelection;
  final List<T> currentSelection;
  final List<T> added;
  final List<T> removed;

  /// Creates an [IsarLinksChange] from the starting selection and the current
  /// selection.
  ///
  /// [startingSelection] is the selection of items in the links object before
  /// the change.
  /// [currentSelection] is the selection of items in the links object after
  /// the change.
  IsarLinksChange({
    required List<T> startingSelection,
    required List<T> currentSelection,
  }) :
    startingSelection = startingSelection,
    currentSelection = currentSelection,
    added = currentSelection.where((e) => !startingSelection.contains(e)).toList(),
    removed = startingSelection.where((e) => !currentSelection.contains(e)).toList();


  /// Returns a new [IsarLinksChange] that results from the starting selection of this
  /// [IsarLinksChange] and the current selection of the [other] [IsarLinksChange].
  ///
  /// This is useful for UI scenarios where the user might make multiple changes
  /// before committing them to the DB, and allows using [currentSelection] for UI
  /// state.
  IsarLinksChange<T> append(IsarLinksChange<T> other) {
    return IsarLinksChange(
      startingSelection: startingSelection,
      currentSelection: other.currentSelection,
    );
  }

  @override
  String toString() {
    return "IsarLinksChange(added: $added, removed: $removed)";
  }
}

(T?, Iterable<T>) buildQueryElementLists<T>(Iterable<T> elements, T? where) {
  if(where == null) {
    return (null, elements);
  }
  else {
    return (where, elements.where((element) => element != where));
  }
}