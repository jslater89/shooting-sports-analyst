import 'package:http/http.dart' as http;
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/util.dart';

/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

sealed class MatchSourceError implements ResultErr {
  String get message;
  StackTrace? get stackTrace;

  const MatchSourceError();

  static NotFound get notFound => const NotFound();
  static NetworkError get networkError => const NetworkError();
  static UnsupportedOperation get unsupportedOperation => const UnsupportedOperation();
  static UnsupportedMatchType get unsupportedMatchType => const UnsupportedMatchType();
  static NoCredentials get noCredentials => const NoCredentials();
  static DatabaseError get databaseError => const DatabaseError();
  static NotModified get notModified => const NotModified();
}

class DatabaseError extends MatchSourceError {
  String get message => "Database error";
  StackTrace? get stackTrace => null;
  const DatabaseError();
}

class NetworkError extends MatchSourceError {
  String get message => "Network error";
  StackTrace? get stackTrace => null;
  const NetworkError();
}

class NetworkErrorWithResponse extends MatchSourceError {
  String get message => "Network error: ${response.statusCode} ${response.body}";
  final http.Response response;
  StackTrace? get stackTrace => null;
  NetworkErrorWithResponse(this.response);
}

class UnsupportedMatchType extends MatchSourceError {
  String get message => "Source does not support match type";
  final String? reason;
  StackTrace? get stackTrace => null;
  const UnsupportedMatchType([this.reason]);
}

class UnsupportedOperation extends MatchSourceError {
  String get message => "Source does not support operation";
  StackTrace? get stackTrace => null;
  const UnsupportedOperation();
}

class TypeMismatch extends MatchSourceError {
  String get message => "Match was of unexpected type";
  SportType attemptedWith;
  SportType? detectedType;
  StackTrace? get stackTrace => null;

  TypeMismatch({required this.attemptedWith, this.detectedType});
}

class NotFound extends MatchSourceError {
  String get message => "Not found";
  StackTrace? get stackTrace => null;
  const NotFound();
}

class FormatError extends MatchSourceError {
  String get message => "Error parsing match data: $underlying";
  ResultErr underlying;
  StackTrace? stackTrace;
  FormatError(this.underlying, {this.stackTrace});
}

class GeneralError extends MatchSourceError {
  String get message => underlying.message;
  final ResultErr underlying;
  StackTrace? stackTrace;
  GeneralError(this.underlying, {this.stackTrace});
}

class NoCredentials extends MatchSourceError {
  String get message => "Match source requires credentials";
  StackTrace? get stackTrace => null;
  const NoCredentials();
}

class NotModified extends MatchSourceError {
  String get message => "Not modified";
  StackTrace? get stackTrace => null;
  const NotModified();
}