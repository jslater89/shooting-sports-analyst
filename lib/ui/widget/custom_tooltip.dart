import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shooting_sports_analyst/config/config.dart';
import 'package:shooting_sports_analyst/ui/colors.dart';

/// A custom tooltip that can be used to insert an overlay entry into
/// the overlay stack. Call [insert] and [remove] to manage the overlay entry.
/// 
/// The type parameter [T] is the type of the data being displayed in the tooltip.
/// [data] is checked for equality to determine if the tooltip should be updated.
class CustomTooltip<T> {
  double width;
  double height;
  bool trackMousePosition;
  Widget child;
  Offset? mousePosition;
  T? data;

  CustomTooltip({required this.child, this.width = 150, this.height = 36, this.trackMousePosition = true});
  OverlayEntry? _overlayEntry;
  final GlobalKey _containerKey = GlobalKey();
  Size? _measuredSize;

  void onHover(PointerHoverEvent event) {
    mousePosition = event.position;
    if(trackMousePosition) {
      _overlayEntry?.markNeedsBuild();
    }
  }

  WidgetBuilder get builder => (context) {
    final uiScaleFactor = ChangeNotifierConfigLoader().uiConfig.uiScaleFactor;
    var windowSize = MediaQuery.of(context).size;
    var mousePosition = this.mousePosition;
    if(mousePosition == null) {
      mousePosition = Offset(0, 0);
    }
    
    // Measure the container size after the first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final RenderBox? renderBox = _containerKey.currentContext?.findRenderObject() as RenderBox?;
      if(renderBox != null) {
        final measuredSize = renderBox.size;
        if(_measuredSize != measuredSize) {
          _measuredSize = measuredSize;
          _overlayEntry?.markNeedsBuild();
        }
      }
    });
    
    // Use measured size if available, otherwise fall back to fixed width/height
    final tooltipWidth = _measuredSize?.width ?? width;
    final tooltipHeight = _measuredSize?.height ?? height;
    
    var offset = 25 * uiScaleFactor;
    // tooltip is to the right of the mouse position
    var left = offset + mousePosition.dx;
    // tooltip is above the mouse position
    var top = mousePosition.dy - offset;
    if(left + tooltipWidth > windowSize.width) {
      // move the tooltip to the left when close to the right
      left -= (tooltipWidth + offset * 2);
    }
    if(top - tooltipHeight < 0) {
      // move the tooltip down when close to the top
      top += (tooltipHeight + offset * 2);
    }

    var finalBackgroundColor = ThemeColors.onBackgroundColor(context);
    
    // Hide tooltip until we've measured its size to avoid jitter
    final isMeasured = _measuredSize != null;

    return Stack(
      children: [
        Positioned(
          left: left,
          top: top,
          child: Opacity(
            opacity: isMeasured ? 1.0 : 0.0,
            child: Container(
              key: _containerKey,
              decoration: BoxDecoration(
                color: finalBackgroundColor.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(4),
              ),
              padding: EdgeInsets.all(8),
              child: Material(
                color: Colors.transparent,
                child: child,
              ),
            ),
          ),
        ),
      ],
    );
  };

  /// Insert the tooltip into the overlay stack if the data is different from the previous data.
  /// If the data is the same as the previous data, do nothing.
  /// If the data is different from the previous data, remove the previous tooltip and insert the new one.
  void insert({
    required BuildContext context,
    required T data,
    Widget? child,
    double? width,
    double? height,
  }) {
    if(this.data != null && this.data == data) {
      return;
    }
    if(this.data != null && this.data != data) {
      remove(context);
    }
    this.data = data;
    if(width != null) {
      this.width = width;
    }
    if(child != null) {
      this.child = child;
    }
    _measuredSize = null; // Reset measured size for new content
    _overlayEntry = OverlayEntry(builder: builder);
    Overlay.of(context).insert(_overlayEntry!);
  }

  /// Remove the tooltip from the overlay stack.
  void remove(BuildContext context) {
    _overlayEntry?.remove();
    data = null;
    _overlayEntry = null;
    _measuredSize = null; // Reset measured size
  }
}