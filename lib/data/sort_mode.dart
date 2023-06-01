
enum SortMode {
  score,
  time,
  alphas,
  availablePoints,
  lastName,
  rating,
  classification,
}


extension SortModeDisplayString on SortMode {
  String displayString() {
    switch(this) {
      case SortMode.score:
        return "Score";
      case SortMode.time:
        return "Time";
      case SortMode.alphas:
        return "Alphas";
      case SortMode.availablePoints:
        return "Available Points";
      case SortMode.lastName:
        return "Last Name";
      case SortMode.rating:
        return "Rating";
      case SortMode.classification:
        return "Classification";
    }
  }
}