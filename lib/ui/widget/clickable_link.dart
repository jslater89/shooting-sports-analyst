/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/ui/colors.dart';
import 'package:url_launcher/url_launcher.dart';

class ClickableLink extends StatelessWidget {
  const ClickableLink({
    super.key,
    this.url,
    this.onTap,
    required this.child,
    this.color,
    this.decorateColor = true,
    this.underline = true,
  });


  /// If null, the link color will be determined by the link color in [ThemeColors].
  /// Set [decorateColor] to false to use the standard theme text color.
  final Color? color;

  /// Whether to decorate the text with the link color.
  final bool decorateColor;

  /// Whether to decorate text with a underline.
  final bool underline;

  final Uri? url;
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if(url == null && onTap == null) {
      throw ArgumentError("url and onTap cannot both be null");
    }

    Color? linkColor;
    if(decorateColor) {
      linkColor = color ?? ThemeColors.linkColor(context);
    }


    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          if(url != null) {
            launchUrl(url!);
          }
          else {
            onTap!();
          }
        },
        child: Theme(
          data: Theme.of(context).copyWith(
          textTheme: Theme.of(context).textTheme.copyWith(
            bodyLarge: Theme.of(context).textTheme.bodyLarge!.copyWith(
              color: linkColor,
              decoration: underline ? TextDecoration.underline : null,
              decorationColor: linkColor,
            ),
            bodyMedium: Theme.of(context).textTheme.bodyMedium!.copyWith(
              color: linkColor,
              decoration: underline ? TextDecoration.underline : null,
              decorationColor: linkColor,
            ),
            bodySmall: Theme.of(context).textTheme.bodySmall!.copyWith(
              color: linkColor,
              decoration: underline ? TextDecoration.underline : null,
              decorationColor: linkColor,
            ),
          ),
        ), child: child),
      ),
    );
  }
}