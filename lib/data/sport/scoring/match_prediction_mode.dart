/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

enum MatchPredictionMode {
  none,
  highAvailable,
  averageStageFinish,
  averageHistoricalFinish,
  /// Predict only shooters who have completed at least one stage.
  ratingAwarePartial,
  /// Predict shooters who haven't appeared at the match yet, but are registered.
  ratingAwareFull;

  static List<MatchPredictionMode> dropdownValues(bool includeRatings) {
    if(includeRatings) return values;
    else return [none, highAvailable, averageStageFinish];
  }

  bool get requiresRatings => switch(this) {
    ratingAwarePartial => true,
    ratingAwareFull => true,
    averageHistoricalFinish => true,
    _ => false,
  };

  bool get ratingAware => switch(this) {
    ratingAwarePartial => true,
    ratingAwareFull => true,
    _ => false,
  };

  String get uiLabel => switch(this) {
    none => "None",
    highAvailable => "High available",
    averageStageFinish => "Average stage finish",
    averageHistoricalFinish => "Average finish in ratings",
    ratingAwarePartial => "Rating-aware (seen only)",
    ratingAwareFull => "Rating-aware (all entrants)",
  };
}
