/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';

/// A MatchCalendarSource is a source of match schedule information, namely
/// name and date.
abstract class MatchScheduleSource {
  /// A name suitable for display.
  String get name;

  /// A URL-encodable code for internal identification.
  ///
  /// Match IDs should be prefixed with `code:`, so that they don't overlap in the database,
  /// unless they can be guaranteed unique across all sources.
  String get code;

  /// Retrieve a list of [MatchCalendarEntry]s for a given date. Only the
  /// year and month are considered.
  Future<List<MatchCalendarEntry>> getMatchCalendarEntries(DateTime date);

  /// Whether this source supports retrieving matches for a given week.
  bool get supportsWeekly;

  /// Retrieve a list of [MatchCalendarEntry]s for a given week. "Week" is defined
  /// as the week containing [date], starting on Monday and ending on Sunday (to
  /// catch one-day Sunday matches in the correct week).
  ///
  /// Internally, this counts days backward until it finds a Monday, then looks at
  /// the 7-day period starting on that day.
  ///
  /// If [supportsWeekly] is false, the implementation may throw an exception.
  Future<List<MatchCalendarEntry>> getMatchCalendarEntriesForWeek(DateTime date);

  /// Whether this source supports retrieving matches for a given day.
  bool get supportsDaily;

  /// Retrieve a list of [MatchCalendarEntry]s for a given day.
  ///
  /// If [supportsDaily] is false, the implementation may throw an exception.
  Future<List<MatchCalendarEntry>> getMatchCalendarEntriesForDay(DateTime date);
}

class MatchCalendarEntry with DbSportEntity {
  String sportName;
  String matchName;
  DateTime startDate;
  DateTime endDate;
  String? practiscoreRegistrationUrl;

  MatchCalendarEntry({
    required this.sportName,
    required this.matchName,
    required this.startDate,
    required this.endDate,
    this.practiscoreRegistrationUrl,
  });
}
