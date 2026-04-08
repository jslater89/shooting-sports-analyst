/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

/// RatingRowData is a data class that contains a single data point within a rating
/// key or row. It serves as a bridge between the no-UI-imports-allowed core rating
/// engine and the UI code that displays the rating data.
class RatingRowData {
  final String data;
  final String? tooltip;
  final bool fadeText;
  final AbstractAlignment alignment;
  final int flex;

  RatingRowData({
    required this.data,
    this.tooltip,
    this.fadeText = false,
    this.alignment = AbstractAlignment.start,
    this.flex = 1,
  });
}

enum AbstractAlignment {
  start,
  center,
  end,
}