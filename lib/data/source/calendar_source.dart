/// A MatchCalendarSource is a source of match schedule information by month,
/// week, or day (the latter two optionally).

abstract class MatchCalendarSource {
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

class MatchCalendarEntry {
  String matchName;
  DateTime startDate;
  DateTime endDate;
  String? practiscoreRegistrationUrl;

  MatchCalendarEntry({
    required this.matchName,
    required this.startDate,
    required this.endDate,
    this.practiscoreRegistrationUrl,
  });
}
