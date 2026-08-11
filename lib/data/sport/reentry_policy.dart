/// A policy for handling reentries in combined-history contexts, such
/// as ratings and career histories.
enum ReentryPolicy {
  /// Only the first entry at a match is considered. All others are ignored.
  ///
  /// "First" may not necessarily be chronological, depending on the match data
  /// source.
  ignoreReentries,

  /// Multiple entries are allowed, but only the best entry is considered.
  bestEntryOnly,

  /// Multiple entries are allowed, and all are considered.
  ///
  /// This means that a logical 'match appearance' is (match, division), rather than
  /// just (match).
  reentriesAllowed;

  /// Whether a competitor can only appear once at a match.
  bool get singleMatchAppearance => this == ignoreReentries || this == bestEntryOnly;

  /// Whether a competitor can appear multiple times at a match.
  bool get multiMatchAppearance => !singleMatchAppearance;
}