/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "package:flutter_test/flutter_test.dart";
import "package:shooting_sports_analyst/data/cache/lru_tracker.dart";
import "package:shooting_sports_analyst/util.dart";

/// Key class that uses a list of strings, sorts for equality, and uses
/// [combineHashList64] for hashCode.
class TestLruKey {
  final List<String> parts;

  TestLruKey(this.parts);

  List<String> get _sorted => parts.toList()..sort();

  @override
  bool operator ==(Object other) {
    if (other is! TestLruKey) return false;
    var a = _sorted;
    var b = other._sorted;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => combineHashList64(_sorted.map((e) => e.hashCode).toList());
}

void main() {
  group("LruTracker", () {
    test("constructor throws for capacity < 1", () {
      expect(() => LruTracker<TestLruKey>(capacity: 0), throwsArgumentError);
      expect(() => LruTracker<TestLruKey>(capacity: -1), throwsArgumentError);
    });

    test("record adds key and returns null when under capacity", () {
      var tracker = LruTracker<TestLruKey>(capacity: 3);
      var key = TestLruKey(["foo", "bar", "baz"]);
      expect(tracker.record(key), isNull);
      expect(tracker.length, equals(1));
      expect(tracker.contains(key), isTrue);
      expect(tracker.isFull, isFalse);
    });

    test("record evicts least-recently-used when over capacity", () {
      var tracker = LruTracker<TestLruKey>(capacity: 2);
      var first = TestLruKey(["foo"]);
      var second = TestLruKey(["bar"]);
      var third = TestLruKey(["baz"]);
      expect(tracker.record(first), isNull);
      expect(tracker.record(second), isNull);
      expect(tracker.record(third), equals(first));
      expect(tracker.length, equals(2));
      expect(tracker.contains(first), isFalse);
      expect(tracker.contains(second), isTrue);
      expect(tracker.contains(third), isTrue);
    });

    test("record re-insert moves key to most-recent (touch)", () {
      var tracker = LruTracker<TestLruKey>(capacity: 2);
      var a = TestLruKey(["a"]);
      var b = TestLruKey(["b"]);
      var c = TestLruKey(["c"]);
      tracker.record(a);
      tracker.record(b);
      tracker.record(a);
      var evicted = tracker.record(c);
      expect(evicted, equals(b));
      expect(tracker.contains(a), isTrue);
      expect(tracker.contains(c), isTrue);
    });

    test("recordAll records in order and returns all evicted keys", () {
      var tracker = LruTracker<TestLruKey>(capacity: 2);
      var keys = [
        TestLruKey(["1"]),
        TestLruKey(["2"]),
        TestLruKey(["3"]),
        TestLruKey(["4"]),
      ];
      var evicted = tracker.recordAll(keys);
      expect(evicted.length, equals(2));
      expect(evicted[0], equals(TestLruKey(["1"])));
      expect(evicted[1], equals(TestLruKey(["2"])));
      expect(tracker.length, equals(2));
      expect(tracker.contains(TestLruKey(["3"])), isTrue);
      expect(tracker.contains(TestLruKey(["4"])), isTrue);
    });

    test("remove takes key out of tracking", () {
      var tracker = LruTracker<TestLruKey>(capacity: 5);
      var key = TestLruKey(["foo", "bar", "baz"]);
      tracker.record(key);
      expect(tracker.contains(key), isTrue);
      tracker.remove(key);
      expect(tracker.contains(key), isFalse);
      expect(tracker.length, equals(0));
    });

    test("contains is true when key present, false when not", () {
      var tracker = LruTracker<TestLruKey>(capacity: 5);
      var key = TestLruKey(["foo", "bar", "baz"]);
      expect(tracker.contains(key), isFalse);
      tracker.record(key);
      expect(tracker.contains(key), isTrue);
      tracker.remove(key);
      expect(tracker.contains(key), isFalse);
    });

    test("clear empties tracker", () {
      var tracker = LruTracker<TestLruKey>(capacity: 5);
      tracker.record(TestLruKey(["foo"]));
      tracker.record(TestLruKey(["bar"]));
      tracker.clear();
      expect(tracker.length, equals(0));
      expect(tracker.isFull, isFalse);
      expect(tracker.contains(TestLruKey(["foo"])), isFalse);
      expect(tracker.contains(TestLruKey(["bar"])), isFalse);
    });

    test("custom key equality is order-independent (sorted)", () {
      var tracker = LruTracker<TestLruKey>(capacity: 5);
      var key1 = TestLruKey(["foo", "bar", "baz"]);
      var key2 = TestLruKey(["baz", "foo", "bar"]);
      tracker.record(key1);
      expect(tracker.contains(key2), isTrue);
      expect(tracker.length, equals(1));
    });

    test("isFull true when at or over capacity", () {
      var tracker = LruTracker<TestLruKey>(capacity: 2);
      expect(tracker.isFull, isFalse);
      tracker.record(TestLruKey(["a"]));
      expect(tracker.isFull, isFalse);
      tracker.record(TestLruKey(["b"]));
      expect(tracker.isFull, isTrue);
    });
  });
}
