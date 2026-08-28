/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/ui/workspace/workspace.dart';

/// Publishes [section] / [detail] to the enclosing [Workspace] only while this
/// route is the current route (so off-stage pages under the stack cannot
/// overwrite the tab title).
class WorkspaceLabelReporter extends StatefulWidget {
  const WorkspaceLabelReporter({
    super.key,
    required this.section,
    this.detail,
    required this.child,
  });

  final String section;
  final String? detail;
  final Widget child;

  @override
  State<WorkspaceLabelReporter> createState() => _WorkspaceLabelReporterState();
}

class _WorkspaceLabelReporterState extends State<WorkspaceLabelReporter> with RouteAware {
  Workspace? _workspace;
  bool _isCurrent = false;
  bool _subscribed = false;
  bool _publishScheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final workspace = Workspace.maybeOf(context);
    if(workspace == null) {
      return;
    }
    final route = ModalRoute.of(context);
    if(route == null) {
      return;
    }
    if(_workspace != workspace || !_subscribed) {
      _workspace?.routeObserver.unsubscribe(this);
      _workspace = workspace;
      _workspace!.routeObserver.subscribe(this, route);
      _subscribed = true;
    }
    // In-route swaps (e.g. ratings configure -> view) remount this widget on an
    // already-current route, so didPush will not fire again.
    if(route.isCurrent) {
      _isCurrent = true;
      _schedulePublish();
    }
  }

  @override
  void dispose() {
    _workspace?.routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant WorkspaceLabelReporter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if(oldWidget.section != widget.section || oldWidget.detail != widget.detail) {
      _schedulePublish();
    }
  }

  void _publish() {
    if(!_isCurrent) {
      return;
    }
    _workspace?.setLabel(section: widget.section, detail: widget.detail);
  }

  /// Route callbacks and [didChangeDependencies] can fire during pop transitions;
  /// defer publishing so tab updates do not relayout chrome mid-activation.
  void _schedulePublish() {
    if(_publishScheduled) {
      return;
    }
    _publishScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _publishScheduled = false;
      if(mounted) {
        _publish();
      }
    });
  }

  @override
  void didPush() {
    _isCurrent = true;
    _schedulePublish();
  }

  @override
  void didPopNext() {
    _isCurrent = true;
    _schedulePublish();
  }

  @override
  void didPushNext() {
    _isCurrent = false;
  }

  @override
  void didPop() {
    _isCurrent = false;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
