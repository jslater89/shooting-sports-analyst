/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/ui/colors.dart';
import 'package:url_launcher/url_launcher.dart';

class ClickableLink extends StatefulWidget {
  const ClickableLink({
    super.key,
    this.url,
    this.onTap,
    required this.child,
    this.color,
    this.decorateTextColor = true,
    this.decorateIconColor = true,
    this.underline = true,
    this.hoverColor,
    this.decorateIconHoverColor = false,
  });


  /// If null, the link color will be determined by the link color in [ThemeColors].
  /// Set [decorateTextColor] to false to use the standard theme text color.
  final Color? color;

  /// If null, the link color will remain the same when hovered. If present, the
  /// link color will be replaced with this color when hovered.
  final Color? hoverColor;

  /// Whether to decorate text with the link color.
  final bool decorateTextColor;

  /// Whether to decorate icons with the link color when not hovered.
  final bool decorateIconColor;

  /// Whether to decorate icons with the hover color when hovered.
  final bool decorateIconHoverColor;

  /// Whether to decorate text with a underline.
  final bool underline;

  final Uri? url;
  final VoidCallback? onTap;
  final Widget child;

  @override
  State<ClickableLink> createState() => _ClickableLinkState();
}

class _ClickableLinkState extends State<ClickableLink> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    if(widget.url == null && widget.onTap == null) {
      throw ArgumentError("url and onTap cannot both be null");
    }

    Color? linkColor;
    if(widget.decorateTextColor) {
      linkColor = widget.color ?? ThemeColors.linkColor(context);
    }

    Color? iconColor;
    if(widget.decorateIconColor) {
      if(widget.hoverColor != null && widget.decorateIconHoverColor && _hovering) {
        iconColor = widget.hoverColor;
      }
      else if(!_hovering) {
        iconColor = linkColor;
      }
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (event) => setState(() => _hovering = true),
      onExit: (event) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: () {
          if(widget.url != null) {
            launchUrl(widget.url!);
          }
          else {
            widget.onTap!();
          }
        },
        child: Theme(
          data: Theme.of(context).copyWith(
            iconTheme: iconColor != null ? Theme.of(context).iconTheme.copyWith(
              color: iconColor,
            ) : null,
            textTheme: Theme.of(context).textTheme.copyWith(
              bodyLarge: Theme.of(context).textTheme.bodyLarge!.copyWith(
                color: linkColor,
                decoration: widget.underline ? TextDecoration.underline : null,
                decorationColor: linkColor,
              ),
              bodyMedium: Theme.of(context).textTheme.bodyMedium!.copyWith(
                color: linkColor,
                decoration: widget.underline ? TextDecoration.underline : null,
                decorationColor: linkColor,
              ),
              bodySmall: Theme.of(context).textTheme.bodySmall!.copyWith(
                color: linkColor,
                decoration: widget.underline ? TextDecoration.underline : null,
                decorationColor: linkColor,
              ),
            ),
          ), child: widget.child
        ),
      ),
    );
  }
}