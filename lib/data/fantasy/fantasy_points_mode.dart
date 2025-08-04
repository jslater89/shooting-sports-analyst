
enum FantasyPointsMode {
  off,
  byDivision,
  currentFilters;

  String get uiLabel => switch(this) {
    off => "Off",
    byDivision => "By division",
    currentFilters => "Current filters",
  };
}
