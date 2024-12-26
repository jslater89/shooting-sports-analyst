/*
MIT License

Copyright (c) 2021 Tamim Arafat

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/

// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

// Source: https://github.com/arafatamim/ticker_text
// TODO: once I figure out issues, send a PR

import 'package:flutter/material.dart';
import 'package:fading_edge_scrollview/fading_edge_scrollview.dart';
import 'package:shooting_sports_analyst/logger.dart';

SSALogger _log = SSALogger("TickerTextController");

class TickerTextController extends ChangeNotifier {
  bool _started;
  bool _paused;

  /// Check if scrolling has started
  bool get started => _started;
  bool get paused => _paused;

  TickerTextController({bool autoStart = false}) : _started = autoStart, _paused = false;

  void startScroll() {
    // _log.v("startScroll");
    _started = true;
    notifyListeners();
  }

  void togglePause() {
    _paused = !_paused;
    // _log.v("togglePause: $_paused");
    notifyListeners();
  }

  void stopScroll() {
    _started = false;
    // _log.v("stopScroll");
    notifyListeners();
  }
}

var _wLog = SSALogger("TickerTextWidget");

class TickerText extends StatefulWidget {
  final Widget child;
  final Axis scrollDirection;

  /// Speed at which the widget scrolls in pixels per second.
  /// Has to be greater than zero.
  final int speed;

  /// How long it takes for the widget to scroll back up from the end.
  final Duration returnDuration;

  /// How long it takes for widget to begin scrolling.
  final Duration startPauseDuration;

  /// How long the scrolling pauses at the end before scrolling back up.
  /// If null, it is the same as [startPauseDuration].
  final Duration? endPauseDuration;

  /// Controls the state of scrolling. If not provided, uses its default internal controller
  /// with `autoStart` enabled.
  final TickerTextController? controller;

  final Curve primaryCurve;

  final Curve returnCurve;

  /// Creates a widget that scrolls to reveal child contents if it overflows,
  /// and scrolls back up when it reaches the end.
  /// Optionally accepts a [TickerTextController] to control scroll behavior.
  ///
  /// Example:
  /// ```
  /// TickerText(
  ///   scrollDirection: Axis.horizontal,
  ///   speed: 20,
  ///   startPauseDuration: const Duration(milliseconds: 500),
  ///   endPauseDuration: const Duration(seconds: 2),
  ///   child: Text("Very long paragraph of text...")
  /// );
  /// ```
  const TickerText({
    Key? key,
    required this.child,
    this.scrollDirection = Axis.horizontal,
    this.returnDuration = const Duration(milliseconds: 800),
    this.startPauseDuration = const Duration(seconds: 10),
    this.endPauseDuration,
    this.speed = 20,
    this.controller,
    this.primaryCurve = Curves.linear,
    this.returnCurve = Curves.easeOut,
  })  : assert(speed > 0, "Speed has to be greater than zero"),
        super(key: key);

  @override
  State<TickerText> createState() => _TickerTextState();
}

class _TickerTextState extends State<TickerText> {
  late final ScrollController _scrollController;
  late final TickerTextController _autoScrollController;

  double get maxScrollExtent => _scrollController.position.maxScrollExtent;
  Duration get scrollDuration => Duration(
        milliseconds: ((maxScrollExtent / widget.speed) * 1000).toInt(),
      );

  @override
  void initState() {
    // _log.v("initState");
    _scrollController = ScrollController(initialScrollOffset: 0.0);
    _autoScrollController =
        widget.controller ?? TickerTextController(autoStart: true);
    if (_autoScrollController.started) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scroll();
      });
    } else {
      _autoScrollController.addListener(_scroll);
    }

    super.initState();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _autoScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadingEdgeScrollView.fromSingleChildScrollView(
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        scrollDirection: widget.scrollDirection,
        controller: _scrollController,
        child: widget.child,
      ),
    );
  }

  bool _scrollRunning = false;

  void _scroll() async {
    // stopping a running scroll continues so it gets canceled.
    // stopping a non-running scroll is a no-op.
    // starting a running scroll is a no-op.
    // starting a non-running scroll continues to start it.
    if(_scrollRunning) {
      if(!_autoScrollController.started) {
        _scrollRunning = false;
      }
      else {
        return;
      }
    }

    // _wLog.v("Scroll controller has clients: ${_scrollController.hasClients}");
    // _wLog.v("Scroll controller offset: ${_scrollController.offset}");
    // _wLog.v("Auto scroll controller started: ${_autoScrollController.started}");
    if (_scrollController.hasClients &&
        _scrollController.offset > 0 &&
        !_autoScrollController.started) {
      _scrollController.jumpTo(0);
      return;
    }

    _scrollRunning = true;
    while (_scrollController.hasClients && _autoScrollController.started) {
      // Run futures in succession
      // _wLog.vv("start, delaying ${widget.startPauseDuration}");
      await Future.delayed(widget.startPauseDuration).then((_) {
        // _wLog.vv("start, animating $maxScrollExtent over $scrollDuration");
        if (_scrollController.hasClients &&
            _autoScrollController.started &&
            _scrollController.offset == 0) {
          return _scrollController.animateTo(
            maxScrollExtent,
            duration: scrollDuration,
            curve: widget.primaryCurve,
          );
        }
      }).then((_) {
        // _wLog.vv("end, delaying ${widget.endPauseDuration ?? widget.startPauseDuration}");
        if (_scrollController.hasClients &&
            _autoScrollController.started &&
            _scrollController.offset >= maxScrollExtent) {
          return Future.delayed(
            widget.endPauseDuration ?? widget.startPauseDuration,
          );
        }
      }).then((_) {
        // _wLog.vv("return, animating 0 over ${widget.returnDuration}");
        if (_scrollController.hasClients &&
            _scrollController.offset >= maxScrollExtent) {
          return _scrollController.animateTo(
            0.0,
            duration: widget.returnDuration,
            curve: widget.returnCurve,
          );
        }
      });
    }
    _scrollRunning = false;
    // _wLog.v("Scroll loop finished");
  }
}
