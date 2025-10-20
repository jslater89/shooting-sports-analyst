/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/ui/colors.dart';

class ConstrainedTooltip extends StatelessWidget {
  const ConstrainedTooltip({super.key, required this.message, required this.child, required this.constraints, this.waitDuration});

  final String message;
  final Widget child;
  final BoxConstraints constraints;
  final Duration? waitDuration;

  @override
  Widget build(BuildContext context) {
    var style = Theme.of(context).textTheme.bodySmall!.copyWith(color: ThemeColors.onBackgroundColor(context));
    return Tooltip(
      waitDuration: waitDuration,
      richMessage: WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: Container(
          constraints: constraints,
          child: Text(message, style: style),
        ),
      ),
      child: child,
    );
  }
}
