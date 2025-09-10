/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

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
