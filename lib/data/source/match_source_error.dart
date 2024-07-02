import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/util.dart';

/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

sealed class MatchSourceError implements ResultErr {
  String get message;

  const MatchSourceError();

  static NotFound get notFound => const NotFound();
  static NetworkError get networkError => const NetworkError();
  static UnsupportedOperation get unsupportedOperation => const UnsupportedOperation();
  static UnsupportedMatchType get unsupportedMatchType => const UnsupportedMatchType();
}

class NetworkError extends MatchSourceError {
  String get message => "Network error";
  const NetworkError();
}

class UnsupportedMatchType extends MatchSourceError {
  String get message => "Source does not support match type";
  final String? reason;
  const UnsupportedMatchType([this.reason]);
}

class UnsupportedOperation extends MatchSourceError {
  String get message => "Source does not support operation";
  const UnsupportedOperation();
}

class TypeMismatch extends MatchSourceError {
  String get message => "Match was of unexpected type";
  SportType attemptedWith;
  SportType? detectedType;

  TypeMismatch({required this.attemptedWith, this.detectedType});
}

class NotFound extends MatchSourceError {
  String get message => "Not found";
  const NotFound();
}

class FormatError extends MatchSourceError {
  String get message => "Error parsing match data";
  ResultErr underlying;

  FormatError(this.underlying);
}