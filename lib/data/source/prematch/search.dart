/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/data/source/match_source_error.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/util.dart';

typedef SearchSourceResult = Result<List<SearchSourceHit>, MatchSourceError>;

/// A SearchSource is a source that can be used to search for matches,
/// either by date, by name, or both.
abstract class SearchSource {
  /// The name of the source.
  String get name;

  /// The code of the source.
  String get code;

  /// The supported sports of the source.
  List<Sport> get supportedSports;

  /// Whether the source is implemented (true) or a stub (false).
  bool get isImplemented => false;

  bool get canSearchByName => false;
  Future<SearchSourceResult> searchByName(String name, {List<Sport>? sportFilter}) {
    return Future.value(Result.err(MatchSourceError.unsupportedOperation));
  }

  bool get canSearchByDateRange => false;
  Future<SearchSourceResult> searchByDateRange(DateTime startDate, DateTime endDate, {List<Sport>? sportFilter}) {
    return Future.value(Result.err(MatchSourceError.unsupportedOperation));
  }

  bool get canSearchByMonth => false;
  /// Search for matches in a given month. Fields other than
  /// year and month will be ignored.
  Future<SearchSourceResult> searchByMonth(DateTime date, {List<Sport>? sportFilter}) {
    return Future.value(Result.err(MatchSourceError.unsupportedOperation));
  }

  bool get canSearchByWeek => false;
  /// Search for matches in the week containing [date].
  Future<SearchSourceResult> searchByWeek(DateTime date, {List<Sport>? sportFilter}) {
    return Future.value(Result.err(MatchSourceError.unsupportedOperation));
  }

  bool get canSearchByDay => false;
  /// Search for matches on a given day. Fields other than
  /// year, month, and day will be ignored.
  Future<SearchSourceResult> searchByDay(DateTime date, {List<Sport>? sportFilter}) {
    return Future.value(Result.err(MatchSourceError.unsupportedOperation));
  }
}

class SearchSourceHit {
  /// The sport of the match, if it can be detected from the search result.
  Sport? sport;

  /// The name of the match.
  String name;

  /// A type hint for the match type local to the source, which can
  /// be used for tight integrations between a search source and a match source.
  String? internalMatchType;

  /// A subtype hint for the match subtype local to the source, which can
  /// be used for tight integrations between a search source and a match source.
  String? internalMatchSubtype;

  /// The date of the match, if available.
  DateTime? date;

  /// The code for a match source that can be used to download this match.
  String? sourceCodeForDownload;

  /// The source IDs for the source specified by [sourceCodeForDownload].
  List<String> sourceIdsForDownload;

  SearchSourceHit({
    required this.sport,
    required this.name,
    this.date,
    this.internalMatchType,
    this.internalMatchSubtype,
    this.sourceCodeForDownload,
    this.sourceIdsForDownload = const [],
  });
}
