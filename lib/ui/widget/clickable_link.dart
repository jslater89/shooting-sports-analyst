import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class ClickableLink extends StatelessWidget {
  const ClickableLink({
    super.key,
    this.url,
    this.onTap,
    required this.child,
  });

  final Uri? url;
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if(url == null && onTap == null) {
      throw ArgumentError("url and onTap cannot both be null");
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
        child: child,
      ),
    );
  }
}