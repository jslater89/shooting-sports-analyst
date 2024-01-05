/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */


enum SortMode {
  // Things that every sport supports, or for which we can
  // determine support for automatically
  score,
  time,
  lastName,
  rating,
  classification,

  // Things sports need to declare they support
  alphas,
  availablePoints,
  rawTime,
  /// IDPA accuracy sorting sorts by IDPA 'most accurate':
  /// sort by non-threats ASC then points down ASC
  idpaAccuracy;

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
      case SortMode.rawTime:
        return "Raw Time";
      case SortMode.idpaAccuracy:
        return "Accuracy";
    }
  }
}