/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';

class ThemeColors {
  static Color backgroundColor(BuildContext context, {int? rowIndex}) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    if(rowIndex == null) {
      return isDark ? Colors.grey[850]! : Colors.white;
    }

    if(isDark) {
      return rowIndex % 2 == 0 ? Colors.grey[850]! : Colors.grey[800]!;
    }
    else {
      return rowIndex % 2 == 0 ? Colors.white : Colors.grey[300]!;
    }
  }

  static Color onBackgroundColor(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    if(isDark) {
      return Colors.grey[300]!;
    }
    else {
      return Colors.black;
    }
  }

  static Color onBackgroundColorFaded(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    if(isDark) {
      return Colors.grey[500]!;
    }
    else {
      return Colors.grey[700]!;
    }
  }

  static Color linkColor(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    if(isDark) {
      return Theme.of(context).colorScheme.primary;
    }
    else {
      return Theme.of(context).colorScheme.tertiary;
    }
  }

  static Color alertRedColor(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    if(isDark) {
      // Brighter/lighter red for dark background
      return const Color.fromARGB(255, 173, 73, 73); // #FF5050
    }
    else {
      // Darker/deeper red for light background
      return const Color.fromARGB(255, 109, 7, 0);
    }
  }
}
