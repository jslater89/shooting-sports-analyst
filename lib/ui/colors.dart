import 'package:flutter/material.dart';

class ThemeColors {
  static Color backgroundColor(BuildContext context, {int? rowIndex}) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    if(rowIndex == null) {
      return isDark ? Colors.grey[900]! : Colors.white;
    }

    if(isDark) {
      return rowIndex % 2 == 0 ? Colors.grey[900]! : Colors.grey[800]!;
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
    return onBackgroundColor(context).withOpacity(0.65);
  }
}
