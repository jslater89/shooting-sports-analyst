/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:intl/intl.dart';

final DateFormat programmerYmdFormat = DateFormat("yyyy-MM-dd");

abstract class ResultErr {
  String get message;
  const ResultErr();
}

class NativeError extends ResultErr {
  String get message => "$e";
  Error e;
  NativeError(this.e);
}

class NativeException extends ResultErr {
  String get message => "$e";
  Exception e;
  NativeException(this.e);
}

class StringError extends ResultErr {
  final String message;

  const StringError(this.message);
}

// My Rust is showing
class Result<T, E extends ResultErr> {
  final T? _result;
  final E? _error;

  bool isOk() {
    return _result != null;
  }

  bool isErr() {
    return _error != null;
  }

  T unwrap() {
    return _result!;
  }

  E unwrapErr() {
    return _error!;
  }

  Result.ok(T result) : this._result = result, this._error = null;
  Result.err(E error) : this._error = error, this._result = null;
  Result.errFrom(Result<Object?, E> other) : this._error = other.unwrapErr(), this._result = null;
}

List<int> mode(List<int> data) {
  var freq = <int, int>{};
  var maxFreq = 0;

  for(var n in data) {
    freq[n] ??= 0;
    freq[n] = freq[n]! + 1;
    if(freq[n]! > maxFreq) {
      maxFreq = freq[n]!;
    }
  }

  return freq.entries.where((e) => e.value == maxFreq).map((e) => e.key).toList();
}

extension IncrementHistogram<T> on Map<T, int> {
  /// Increase the value of this[key] by 1.
  void increment(T key) {
    incrementBy(key, 1);
  }

  /// Increase the value of this[key] by [amount].
  void incrementBy(T key, int amount) {
    var value = this[key] ?? 0;
    value += amount;
    this[key] = value;
  }
}

extension ListMap<K, V> on Map<K, List<V>> {
  void addToList(K key, V value) {
    this[key] ??= [];
    var list = this[key]!;
    list.add(value);
  }
}

/// FNV-1a 64bit hash algorithm optimized for Dart Strings
extension StableStringHash on String {
  int get stableHash {
    var hash = 0xcbf29ce484222325;

    var i = 0;
    while (i < length) {
      final codeUnit = codeUnitAt(i++);
      hash ^= codeUnit >> 8;
      hash *= 0x100000001b3;
      hash ^= codeUnit & 0xFF;
      hash *= 0x100000001b3;
    }

    return hash;
  }
}

extension StableIntHash on int {
  int get stableHash {
    var x = ((this >> 16) ^ this) * 0x45d9f3b;
    x = ((x >> 16) ^ x) * 0x45d9f3b;
    x = (x >> 16) ^ x;
    return x;
  }
}

extension AsPercentage on double {
  String asPercentage({int decimals = 2}) {
    return (this * 100).toStringAsFixed(decimals);
  }
}

/// A callback used by long-running synchronous processes to allow UI updates
/// and progress display. If UI updates are desired, ProgressCallback should
/// await Future.delayed (or some other async task) to allow the task queue
/// to cycle.
typedef ProgressCallback = Future<void> Function(int progress, int total);

extension SanitizeFilename on String {
  String safeFilename({String replacement = ''}) {
    final result = this.toLowerCase()
        .replaceAll(RegExp(r'\s'), "-"
    )
    // illegalRe
        .replaceAll(
      RegExp(r'[/?<>\\:*|"]'),
      replacement,
    )
        .replaceAll(r"'",
        replacement
    )
    // controlRe
        .replaceAll(
      RegExp(
        r'[\x00-\x1f\x80-\x9f]',
      ),
      replacement,
    )
    // reservedRe
        .replaceFirst(
      RegExp(r'^\.+$'),
      replacement,
    )
    // windowsReservedRe
        .replaceFirst(
      RegExp(
        r'^(con|prn|aux|nul|com[0-9]|lpt[0-9])(\..*)?$',
        caseSensitive: false,
      ),
      replacement,
    )
    // windowsTrailingRe
        .replaceFirst(RegExp(r'[. ]+$'), replacement);

    return result.length > 255 ? result.substring(0, 255) : result;
  }
}