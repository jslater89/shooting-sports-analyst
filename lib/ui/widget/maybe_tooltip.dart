
import 'package:flutter/material.dart';

class MaybeTooltip extends StatelessWidget {
  const MaybeTooltip({super.key, this.message, this.richMessage, required this.child});

  final String? message;
  final InlineSpan? richMessage;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if(message == null && richMessage == null) {
      return child;
    }

    return Tooltip(message: message, richMessage: richMessage, child: child);
  }
}