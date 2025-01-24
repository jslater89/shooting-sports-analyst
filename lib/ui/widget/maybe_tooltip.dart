/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

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