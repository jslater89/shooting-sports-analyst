/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */


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