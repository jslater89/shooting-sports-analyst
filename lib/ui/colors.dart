import 'package:flutter/material.dart';

class ThemeColors {
  static Color backgroundColor(BuildContext context, {int? rowIndex}) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    if(rowIndex == null) {
      return isDark ? Colors.grey[900]! : Colors.grey[200]!;
    }

    if(isDark) {
      return rowIndex % 2 == 0 ? Colors.grey[800]! : Colors.grey[900]!;
    }
    else {
      return rowIndex % 2 == 0 ? Colors.grey[200]! : Colors.white;
    }
  }
}
