import 'package:collection/collection.dart';

class SortedList<T> {
  List<T> _backing = [];
  int Function(T a, T b) comparator;

  SortedList({required this.comparator});

  T operator[](int index) {
    return _backing[index];
  }

  void add(T item) {
    for(int i = 0; i < _backing.length; i++) {
      if(comparator(item, _backing[i]) >= 0) {
        _backing.insert(i, item);
        return;
      }
    }

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

  Iterator<T> get iterator => _backing.iterator;
  Iterable<T> get asIterable => []..addAll(_backing);

  Iterable<T> sorted(int Function(T a, T b) comparator) => _backing.sorted(comparator);
  Iterable<E> map<E>(E toElement(T e)) => _backing.map(toElement);
}