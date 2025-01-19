import 'package:flutter/material.dart';

class ConstrainedTooltip extends StatelessWidget {
  const ConstrainedTooltip({super.key, required this.message, required this.child, required this.constraints, this.waitDuration});

  final String message;
  final Widget child;
  final BoxConstraints constraints;
  final Duration? waitDuration;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      waitDuration: waitDuration,
      richMessage: WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: Container(
          constraints: constraints,
          child: Text(message),
        ),
      ),
      child: child,
    );
  }
}