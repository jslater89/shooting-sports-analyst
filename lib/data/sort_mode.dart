
enum SortMode {
  score,
  time,
  alphas,
  availablePoints,
  lastName,
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
    }
    return "INVALID SORT MODE";
  }
}