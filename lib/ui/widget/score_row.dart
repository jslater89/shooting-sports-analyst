/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/ui/colors.dart';

class ScoreRow extends StatefulWidget {
  final Widget? child;
  final bool? edited;
  final Color? color;
  final int? index;
  final Color? textColor;
  final Color? hoverColor;
  final bool hoverEnabled;
  final Color? hoverTextColor;
  final bool bold;

  const ScoreRow({Key? key, this.bold = true, this.index, this.child, this.color, this.textColor, this.hoverColor, this.hoverEnabled = true, this.hoverTextColor, this.edited}) : super(key: key);

  @override
  State<StatefulWidget> createState() {
    return _ScoreRowState();
  }
}

class _ScoreRowState extends State<ScoreRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    Color background;
    if(widget.index != null && widget.color == null) {
      background = ThemeColors.backgroundColor(context, rowIndex: widget.index);
    }
    else {
      background = widget.color ?? ThemeColors.backgroundColor(context, rowIndex: widget.index);
    }

    Color hoverColor = widget.hoverColor ?? Theme.of(context).colorScheme.primary;
    Color? textColor = widget.textColor ?? Theme.of(context).textTheme.bodyMedium!.color;
    Color hoverTextColor = widget.hoverTextColor ?? Theme.of(context).colorScheme.onPrimary;

    if(widget.edited ?? false) {
      textColor = Colors.red;
    }

    ThemeData baseTheme = Theme.of(context);
    return MouseRegion(
      onHover: (e) => setState(() {
        _hover = true;
      }),
      onExit: (e) => setState(() {
        _hover = false;
      }),
      child: Container(
          color: _hover && widget.hoverEnabled ? hoverColor : background,
          child: Theme(
            child: Builder(
              builder: (context) {
                return DefaultTextStyle(
                  style: widget.bold ?
                      Theme.of(context).textTheme.bodyLarge! :
                      Theme.of(context).textTheme.bodyMedium!,
                  child: widget.child!,
                );
              }
            ),
            data: baseTheme.copyWith(
              textTheme: baseTheme.textTheme.copyWith(
                bodyLarge: baseTheme.textTheme.bodyMedium!.copyWith(
                  color: _hover && widget.hoverEnabled ? hoverTextColor : textColor,
                  fontWeight: FontWeight.w500,
                ),
                bodyMedium: baseTheme.textTheme.bodyMedium!.copyWith(
                  color: _hover && widget.hoverEnabled ? hoverTextColor : textColor,
                ),
              )
            ),
          )
      ),
    );
  }

}
