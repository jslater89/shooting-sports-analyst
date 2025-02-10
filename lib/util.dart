/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:ui';

import 'package:collection/collection.dart';
import 'package:flutter/widgets.dart';
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

  static Result<T, NativeError> result<T>(Error e) {
    return Result.err(NativeError(e));
  }
}

class NativeException extends ResultErr {
  String get message => "$e";
  Exception e;
  NativeException(this.e);

  static Result<T, NativeException> result<T>(Exception e) {
    return Result.err(NativeException(e));
  }
}

class StringError extends ResultErr {
  final String message;

  const StringError(this.message);

  static Result<T, StringError> result<T>(String message) {
    return Result.err(StringError(message));
  }
}

typedef Nullable<T> = T?;

// My Rust is showing
class Result<T, E extends ResultErr> {
  bool _ok;
  final T? _result;
  final E? _error;

  bool isOk() {
    return _ok;
  }

  bool isErr() {
    return !_ok;
  }

  T unwrap() {
    if(T == Nullable<T>) {
      return _result as T;
    }
    return _result!;
  }

  E unwrapErr() {
    return _error!;
  }

  Result.ok(T result) : this._result = result, this._error = null, this._ok = true;
  Result.err(E error) : this._error = error, this._result = null, this._ok = false;
  Result.errFrom(Result<Object?, E> other) : this._error = other.unwrapErr(), this._result = null, this._ok = false;
}

extension AsyncResult<T, E extends ResultErr> on Future<Result<T, E>> {
  Future<bool> isOk() async {
    var res = await this;
    return res.isOk();
  }

  Future<bool> isErr() async {
    var res = await this;
    return res.isErr();
  }

  Future<T> unwrap() async {
    var res = await this;
    return res.unwrap();
  }

  Future<E> unwrapErr() async {
    var res = await this;
    return res.unwrapErr();
  }
}

extension ListStatistics<T extends Comparable> on List<T> {
  T get median {
    if(this.isEmpty) throw ArgumentError("empty list");

    late List<T> sorted;
    if(this.isSorted((a, b) => a.compareTo(b))) {
      sorted = this;
    }
    else {
      sorted = this.sorted((a, b) => a.compareTo(b));
    }

    return sorted[sorted.length ~/ 2];
  }
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
  /// Increase the value of [key] in this map by 1.
  void increment(T key) {
    incrementBy(key, 1);
  }

  /// Increase the value of [key] in this map by [amount].
  void incrementBy(T key, int amount) {
    var value = this[key] ?? 0;
    value += amount;
    this[key] = value;
  }
}

extension IncrementDoubleMap<T> on Map<T, double> {
  void incrementBy(T key, double amount) {
    var value = this[key] ?? 0;
    value += amount;
    this[key] = value;
  }
}

extension ListMap<K, V> on Map<K, List<V>> {
  /// Add [value] to the list at [key], creating the list if it doesn't exist.
  void addToList(K key, V value) {
    this[key] ??= [];
    var list = this[key]!;
    list.add(value);
  }

  /// Add [value] to the list at [key], creating the list if it doesn't exist,
  /// but only if [value] is not already in the list.
  bool addToListIfMissing(K key, V value) {
    if(this[key]?.contains(value) ?? false) {
      return false;
    }
    addToList(key, value);
    return true;
  }
}

extension SetMap<K, V> on Map<K, Set<V>> {
  /// Add [value] to the set at [key], creating the set if it doesn't exist.
  void addToSet(K key, V value) {
    this[key] ??= {};
    var set = this[key]!;
    set.add(value);
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

int combineHashes(int hash, int value) {
  hash = 0x1fffffff & (hash + value);
  hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
  return hash ^ (hash >> 6);
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

String yMdHm(DateTime date) {
  return DateFormat.yMd().format(date) + " " + DateFormat.Hm().format(date);
}

extension SetStateIfMounted<T extends StatefulWidget> on State<T> {
  void setStateIfMounted(VoidCallback fn) {
    if(mounted) {
      // ignore: invalid_use_of_protected_member
      setState(fn);
    }
  }
}

extension ListOverlap<T> on Iterable<T> {
  Iterable<T> intersection(Iterable<T> other) {
    return this.where((e) => other.contains(e));
  }

  bool intersects(Iterable<T> other) {
    return this.any((e) => other.contains(e));
  }

  bool containsAll(Iterable<T> other) {
    return other.every((e) => this.contains(e));
  }

  Iterable<T> union(Iterable<T> other) {
    return {...this, ...other};
  }
}

extension Interleave<T> on List<T> {
  List<T> interleave(List<T> other) {
    if(other.length != length && other.length != length - 1) {
      throw ArgumentError("other must have the same length as this, or one less");
    }

    var result = <T>[];
    for(var i = 0; i < length; i++) {
      result.add(this[i]);
      if(i < other.length) {
        result.add(other[i]);
      }
    }

    return result;
  }
}

extension WindowedList<T> on List<T> {
  /// Get a windowed view into the list, optionally offset by [offset],
  /// starting at the head of the list.
  List<T> getWindow(int window, {int offset = 0}) {
    if(offset + window > length) return this;
    return sublist(offset, offset + window);
  }

  /// Get a windowed view into the list, starting at the tail of the list,
  /// optionally offset by [offset].
  List<T> getTailWindow(int window, {int offset = 0}) {
    if(offset + window > length) return this;
    return sublist(length - window - offset, length - offset);
  }
}

/// Linearly interpolate between [minOut], [centerOut], and [maxOut], based on
/// [value] relative to [center].
/// 
/// When [value] <= [centerMinFactor] * [center], the result is [minOut]. 
/// 
/// Between [centerMinFactor] * [center] and [center], the result is linearly
/// interpolated between [minOut] and [centerOut].
/// 
/// When [value] equals [center], the result is [centerOut].
/// 
/// When [value] is between [center] and [centerMaxFactor] * [center], the result
/// is linearly interpolated between [centerOut] and [maxOut].
/// 
/// When [value] >= [centerMaxFactor] * [center], the result is [maxOut].
double lerpAroundCenter({
  required double value,
  required double center,
  double centerMinFactor = 0.5,
  double centerMaxFactor = 2.0,
  double minOut = 0.5,
  double centerOut = 1.0,
  double maxOut = 2.0,
}) {
  var bottom = center * centerMinFactor;
  var top = center * centerMaxFactor;
  if(value <= bottom) return minOut;
  if(value >= top) return maxOut;
  
  // if value is greater than or equal to center, scale up from centerOut to maxOut
  if(value >= center) {
    var range = maxOut - centerOut;
    var scale = (value - center) / (top - center);
    return centerOut + range * scale;
  }
  // if value is less than center, scale down from centerOut to minOut
  else {
    var range = centerOut - minOut;
    var scale = (center - value) / (center - bottom);
    return minOut + range * scale;
  }
}

extension Clamp on num {
  num clamp(num min, num max) {
    if(this < min) return min;
    if(this > max) return max;
    return this;
  }
}
