/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:collection/collection.dart';

class SortedList<T> {
  List<T> _backing = [];
  late int Function(T a, T b) _comparator;

  SortedList({required int Function(T a, T b) comparator}) : _comparator = comparator;
  SortedList.comparable() {
    _comparator = (T a, T b) => (a as Comparable).compareTo(b);
  }
  SortedList.copy(SortedList<T> other) :
      this._backing = <T>[]..addAll(other._backing),
      this._comparator = other._comparator;

  T operator[](int index) {
    return _backing[index];
  }

  List<T> sublist(int start, [int? end]) {
    return _backing.sublist(start, end ?? length);
  }

  void add(T item) {
    if(_backing.length == 0) {
      _backing.add(item);
      return;
    }
    if(_comparator(item, _backing.last) > 0) {
      _backing.add(item);
      return;
    }

    // The first time that the new item is less than
    // the current item, insert it in place of the
    // current item and move everything else right.
    for(int i = 0; i < _backing.length; i++) {
      if(_comparator(item, _backing[i]) <= 0) {
        _backing.insert(i, item);
        return;
      }
    }

    // Otherwise, this is the greatest item in the list, or the first one
    _backing.add(item);
  }

  void remove(T item) {
    _backing.remove(item);
  }

  void removeAll(Iterable<T> items) {
    for(var item in items) {
      _backing.remove(item);
    }
  }

  bool contains(T item) {
    return _backing.contains(item);
  }

  T? firstWhereOrNull(bool Function(T) predicate) {
    return _backing.firstWhereOrNull(predicate);
  }

  void addAll(Iterable<T> items) {
    for(var item in items) add(item);
  }

  int get length => _backing.length;
  T get first => _backing.first;
  T get last => _backing.last;

  /// This returns the backing list directly. Do not modify it,
  /// or the guarantees of SortedList will be lost.
  Iterable<T> get iterable => _backing;
  /// This returns a copy of the backing list.
  Iterable<T> get asIterable => []..addAll(_backing);

  Iterable<T> sorted(int Function(T a, T b) comparator) => _backing.sorted(comparator);
  Iterable<E> map<E>(E toElement(T e)) => _backing.map(toElement);

  @override
  String toString() {
    return _backing.toString();
  }

  bool get isNotEmpty => _backing.isNotEmpty;
  bool get isEmpty => _backing.isEmpty;
}

extension NumericOperations on SortedList<num> {
  num get sum => this._backing.sum;
  num get average => this._backing.average;
}