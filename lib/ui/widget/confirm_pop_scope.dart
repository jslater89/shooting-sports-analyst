/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/widgets.dart';
import 'package:shooting_sports_analyst/ui/workspace/workspace.dart';

class ConfirmPopScope extends StatefulWidget {
  const ConfirmPopScope({super.key, required this.child, required this.onPopRequested});

  final Widget child;
  final Future<bool> Function() onPopRequested;

  @override
  State<ConfirmPopScope> createState() => _ConfirmPopScopeState();
}

class _ConfirmPopScopeState extends State<ConfirmPopScope> {
  bool _confirmedPop = false;
  Workspace? _workspace;
  late final Future<bool> Function() _guard = _runGuard;

  Future<bool> _runGuard() => widget.onPopRequested();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final workspace = Workspace.maybeOf(context);
    if(workspace == _workspace) {
      return;
    }
    _workspace?.removeCloseGuard(_guard);
    _workspace = workspace;
    _workspace?.addCloseGuard(_guard);
  }

  @override
  void dispose() {
    _workspace?.removeCloseGuard(_guard);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _confirmedPop,
      onPopInvokedWithResult: (didPop, result) async {
        final navigator = Navigator.of(context);
        if(!didPop) {
          _confirmedPop = await widget.onPopRequested();
          if(_confirmedPop && context.mounted) {
            navigator.pop(result);
          }
        }
      },
      child: widget.child,
    );
  }
}