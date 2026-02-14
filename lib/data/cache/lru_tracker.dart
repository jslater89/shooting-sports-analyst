/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:collection';

/// A reusable LRU (least-recently-used) eviction tracker.
///
/// This class tracks access order for keys of type [T] and reports which
/// keys should be evicted when capacity is exceeded. It does not store
/// cached values itself — it is a bolt-on component that any cache can
/// compose to get bounded-size LRU behavior.
///
/// Usage:
/// ```dart
/// var tracker = LruTracker<String>(capacity: 1000);
///
/// // On cache write or read hit, record the key:
/// var evicted = tracker.record("some-key");
/// if (evicted != null) {
///   myCache.remove(evicted);
/// }
///
/// // On batch insert:
/// var evictedKeys = tracker.recordAll(["a", "b", "c"]);
/// for (var key in evictedKeys) {
///   myCache.remove(key);
/// }
/// ```
class LruTracker<T> {
  /// The maximum number of keys to track before eviction.
  final int capacity;

  /// Insertion-ordered map used to track access recency.
  ///
  /// The least-recently-used key is at the front; the most-recently-used
  /// key is at the back. On access, keys are removed and re-inserted to
  /// move them to the back.
  final LinkedHashMap<T, void> _accessOrder = LinkedHashMap<T, void>();

  /// Creates an LRU tracker with the given [capacity].
  ///
  /// [capacity] must be at least 1.
  LruTracker({required this.capacity}) {
    if (capacity < 1) {
      throw ArgumentError("LruTracker capacity must be >= 1, got $capacity");
    }
  }

  /// The number of keys currently tracked.
  int get length => _accessOrder.length;

  /// Whether the tracker is at capacity.
  bool get isFull => _accessOrder.length >= capacity;

  /// Record an access for [key], moving it to the most-recently-used position.
  ///
  /// If the tracker exceeds capacity after this insertion, the least-recently-used
  /// key is evicted and returned. Returns `null` if no eviction occurred.
  T? record(T key) {
    // Remove first so re-insert moves to the back (most recent).
    _accessOrder.remove(key);
    _accessOrder[key] = null;

    if (_accessOrder.length > capacity) {
      var evicted = _accessOrder.keys.first;
      _accessOrder.remove(evicted);
      return evicted;
    }
    return null;
  }

  /// Record accesses for all [keys], returning any keys that were evicted.
  ///
  /// Keys are recorded in iteration order; evictions are collected and returned
  /// as a list. The returned list is empty if no evictions occurred.
  List<T> recordAll(Iterable<T> keys) {
    List<T> evicted = [];
    for (var key in keys) {
      var e = record(key);
      if (e != null) {
        evicted.add(e);
      }
    }
    return evicted;
  }

  /// Remove a key from tracking without treating it as an eviction.
  ///
  /// Use this when the cache removes an entry for reasons other than LRU
  /// eviction (e.g., explicit invalidation).
  void remove(T key) {
    _accessOrder.remove(key);
  }

  /// Whether [key] is currently tracked.
  bool contains(T key) => _accessOrder.containsKey(key);

  /// Clear all tracked keys.
  void clear() {
    _accessOrder.clear();
  }
}
