/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:xml/xml.dart';
import 'package:path_drawing/path_drawing.dart';
import 'dart:ui' as ui;

/// A widget that allows for interaction with an SVG file.
///
/// Paths with an ID attribute are considered interactive. Interactive
/// paths will trigger the [onEnter], [onHover], [onExit], and [onClick] callbacks.
///
/// [onEnter] is called when the mouse enters a region bounded by an
/// interactive path. [onExit] is called when the mouse exits a region bounded by an
/// interactive path, and will be called with null when the mouse exits a noninteractive
/// region. [onClick] is called when the user clicks on an interactive path.
/// [onHover] is called when the mouse is moving over an interactive path.
class InteractiveSvg extends StatefulWidget {
  final String assetPath;
  final ColorMapper? colorMapper;
  final double? width;
  final double? height;
  final Function(PointerHoverEvent event, String? pathId)? onHover;
  final Function(PointerHoverEvent event, String? pathId)? onEnter;
  final Function(PointerHoverEvent event, String? pathId)? onExit;
  final Function(PointerDownEvent event, String? pathId)? onClick;

  const InteractiveSvg({
    Key? key,
    required this.assetPath,
    this.colorMapper,
    this.width,
    this.height,
    this.onHover,
    this.onEnter,
    this.onExit,
    this.onClick,
  }) : super(key: key);

  @override
  _InteractiveSvgState createState() => _InteractiveSvgState();
}

class _InteractiveSvgState extends State<InteractiveSvg> {
  Map<String, ui.Path> _svgPaths = {};
  String? _hoveredPathId; // To store the ID of the currently hovered path
  double? _svgWidth;
  double? _svgHeight;
  final GlobalKey _svgKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _loadSvgPaths();
  }

  Future<void> _loadSvgPaths() async {
    final String svgString = await DefaultAssetBundle.of(context).loadString(widget.assetPath);
    final XmlDocument document = XmlDocument.parse(svgString);
    Map<String, ui.Path> svgPaths = {};

    // Extract SVG dimensions
    final svgElement = document.findElements('svg').firstOrNull;
    if (svgElement != null) {
      final String? viewBox = svgElement.getAttribute('viewBox');
      if (viewBox != null) {
        final List<String> viewBoxValues = viewBox.split(RegExp(r'[\s,]+'));
        if (viewBoxValues.length >= 4) {
          _svgWidth = double.tryParse(viewBoxValues[2]);
          _svgHeight = double.tryParse(viewBoxValues[3]);
        }
      }
      if (_svgWidth == null) {
        _svgWidth = double.tryParse(svgElement.getAttribute('width') ?? '');
      }
      if (_svgHeight == null) {
        _svgHeight = double.tryParse(svgElement.getAttribute('height') ?? '');
      }
    }

    var paths = document.findAllElements('path');
    for(var element in paths) {
      final String? pathData = element.getAttribute('d');
      if (pathData != null) {
        var id = element.getAttribute('id');
        if(id == null) {
          // Only elements with IDs are interactive
          continue;
        }
        svgPaths[id] = parseSvgPathData(pathData);
      }
    }

    setState(() {
      _svgPaths = svgPaths;
    });
  }

  Offset _widgetToSvgCoordinates(Offset widgetPosition, Size widgetSize) {
    if (_svgWidth == null || _svgHeight == null) {
      return widgetPosition;
    }

    // Calculate how the SVG is rendered with BoxFit.contain
    final double svgAspectRatio = _svgWidth! / _svgHeight!;
    final double widgetAspectRatio = widgetSize.width / widgetSize.height;

    double scale;
    double offsetX = 0;
    double offsetY = 0;

    if (svgAspectRatio > widgetAspectRatio) {
      // SVG is wider relative to its height - constrained by width
      scale = widgetSize.width / _svgWidth!;
      offsetY = (widgetSize.height - _svgHeight! * scale) / 2;
    } else {
      // SVG is taller relative to its width - constrained by height
      scale = widgetSize.height / _svgHeight!;
      offsetX = (widgetSize.width - _svgWidth! * scale) / 2;
    }

    // Transform widget coordinates to SVG coordinates
    final double svgX = (widgetPosition.dx - offsetX) / scale;
    final double svgY = (widgetPosition.dy - offsetY) / scale;

    return Offset(svgX, svgY);
  }

  void _onHover(PointerHoverEvent event) {
    if (_svgWidth == null || _svgHeight == null) {
      return;
    }

    final RenderBox? renderBox = _svgKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) {
      return;
    }

    final Size widgetSize = renderBox.size;
    final Offset svgPosition = _widgetToSvgCoordinates(event.localPosition, widgetSize);

    String? currentHoveredId;
    for (var pathEntry in _svgPaths.entries) {
      if (pathEntry.value.contains(svgPosition)) {
        currentHoveredId = pathEntry.key;
        break;
      }
    }
    if (currentHoveredId != _hoveredPathId) {
      if(currentHoveredId != null) {
        widget.onExit?.call(event, _hoveredPathId);
      }
      else {
        widget.onExit?.call(event, null);
      }
      widget.onEnter?.call(event, currentHoveredId);

      setState(() {
        _hoveredPathId = currentHoveredId;
      });
    }
    if(currentHoveredId != null) {
      widget.onHover?.call(event, currentHoveredId);
    }
  }

  void _onClick(PointerDownEvent event) {
    if (_svgWidth == null || _svgHeight == null) {
      return;
    }
    final RenderBox? renderBox = _svgKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) {
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _onClick,
      child: MouseRegion(
        onHover: _onHover,
        child: Stack(
          children: [
            SvgPicture.asset(
              key: _svgKey,
              widget.assetPath,
              fit: BoxFit.contain,
              colorMapper: widget.colorMapper,
              width: widget.width,
              height: widget.height,
            ),
          ],
        ),
      ),
    );
  }
}