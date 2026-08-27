/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

/// Label and navigation state for one workspace tab.
class Workspace extends ChangeNotifier {
  Workspace({String section = "Home", String? detail})
      : _section = section,
        _detail = detail;

  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  final RouteObserver<ModalRoute<void>> routeObserver =
      RouteObserver<ModalRoute<void>>();

  String _section;
  String? _detail;
  bool _notifyScheduled = false;
  final List<Future<bool> Function()> _closeGuards = [];

  String get section => _section;
  String? get detail => _detail;

  /// Tab chip text: `section` or `section · detail`.
  String get tabTitle {
    final d = _detail;
    if(d == null || d.isEmpty) {
      return _section;
    }
    return "$_section · $d";
  }

  void addCloseGuard(Future<bool> Function() guard) {
    _closeGuards.add(guard);
  }

  void removeCloseGuard(Future<bool> Function() guard) {
    _closeGuards.remove(guard);
  }

  /// Asks each mounted [ConfirmPopScope] whether this workspace can be
  /// destroyed, innermost first. Does not pop routes.
  Future<bool> requestClose() async {
    final guards = [..._closeGuards.reversed];
    for(final guard in guards) {
      if(!_closeGuards.contains(guard)) {
        continue;
      }
      if(!await guard()) {
        return false;
      }
    }
    return true;
  }

  void setLabel({required String section, String? detail}) {
    if(_section == section && _detail == detail) {
      return;
    }
    _section = section;
    _detail = detail;
    _scheduleNotify();
  }

  /// [WorkspaceLabelReporter] may call [setLabel] from [State.didChangeDependencies],
  /// which runs during build — defer [notifyListeners] until after the frame.
  void _scheduleNotify() {
    final phase = SchedulerBinding.instance.schedulerPhase;
    if(phase == SchedulerPhase.idle || phase == SchedulerPhase.postFrameCallbacks) {
      notifyListeners();
      return;
    }
    if(_notifyScheduled) {
      return;
    }
    _notifyScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notifyScheduled = false;
      if(hasListeners) {
        notifyListeners();
      }
    });
  }

  /// Returns the enclosing [Workspace], or null when not under a workspace shell.
  static Workspace? maybeOf(BuildContext context) {
    try {
      return Provider.of<Workspace>(context, listen: false);
    }
    catch(_) {
      return null;
    }
  }
}
