
enum RatingDisplayMode {
  preMatch,
  postMatch,
  change,
  none;

  String get uiLabel {
    switch(this) {

      case RatingDisplayMode.preMatch:
        return "Pre-match";
      case RatingDisplayMode.postMatch:
        return "Post-match";
      case RatingDisplayMode.change:
        return "Change";
      case RatingDisplayMode.none:
        return "None";
    }
  }
}
