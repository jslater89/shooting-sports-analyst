/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/widgets.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/extensions/application_preferences.dart';
import 'package:shooting_sports_analyst/ui/workspace/workspace.dart';

/// Owns the list of workspaces, selection, and tab-bar expand/collapse.
class WorkspaceManager extends ChangeNotifier {
  static const maxWorkspaces = 6;

  WorkspaceManager() {
    final prefs = AnalystDatabase().getPreferencesSync();
    _barExpanded = prefs.workspaceBarExpanded;
    _attach(_createWorkspace());
  }

  final List<Workspace> _workspaces = [];
  int _selectedIndex = 0;
  bool _barExpanded = true;
  bool _closing = false;

  List<Workspace> get workspaces => List.unmodifiable(_workspaces);
  int get selectedIndex => _selectedIndex;
  bool get barExpanded => _barExpanded;
  Workspace get current => _workspaces[_selectedIndex];
  bool get canAdd => _workspaces.length < maxWorkspaces;
  bool get canCloseSelected => _workspaces.length > 1;

  void select(int index) {
    if(index < 0 || index >= _workspaces.length || index == _selectedIndex) {
      return;
    }
    _selectedIndex = index;
    notifyListeners();
  }

  /// Opens a new workspace at the main menu, if under the cap.
  void addWorkspace() {
    if(!canAdd) {
      return;
    }
    _attach(_createWorkspace());
    _selectedIndex = _workspaces.length - 1;
    notifyListeners();
  }

  /// Selects [index], runs [ConfirmPopScope] close guards, and removes the
  /// tab only if none of them veto. Background tabs are brought on-stage
  /// first so confirmation dialogs have a visible overlay, then the
  /// previously selected workspace is restored.
  Future<void> closeWorkspace(int index) async {
    if(_closing) {
      return;
    }
    if(_workspaces.length <= 1) {
      return;
    }
    if(index < 0 || index >= _workspaces.length) {
      return;
    }

    final previouslySelected = _workspaces[_selectedIndex];

    _closing = true;
    try {
      if(!_barExpanded) {
        setBarExpanded(true);
      }
      select(index);
      await WidgetsBinding.instance.endOfFrame;

      if(index < 0 || index >= _workspaces.length) {
        return;
      }
      final workspace = _workspaces[index];
      if(!await workspace.requestClose()) {
        _restoreSelection(previouslySelected);
        return;
      }

      final removeAt = _workspaces.indexOf(workspace);
      if(removeAt < 0 || _workspaces.length <= 1) {
        _restoreSelection(previouslySelected);
        return;
      }

      _workspaces.removeAt(removeAt);
      _detach(workspace);
      if(previouslySelected != workspace) {
        _restoreSelection(previouslySelected, notify: false);
      }
      else if(_selectedIndex >= _workspaces.length) {
        _selectedIndex = _workspaces.length - 1;
      }
      notifyListeners();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        workspace.dispose();
      });
    }
    finally {
      _closing = false;
    }
  }

  void _restoreSelection(Workspace workspace, {bool notify = true}) {
    final restoreAt = _workspaces.indexOf(workspace);
    if(restoreAt < 0 || restoreAt == _selectedIndex) {
      return;
    }
    _selectedIndex = restoreAt;
    if(notify) {
      notifyListeners();
    }
  }

  /// Moves the workspace at [from] so it ends up at index [to], keeping the
  /// same workspace selected by identity.
  void reorder(int from, int to) {
    if(from == to) {
      return;
    }
    if(from < 0 || to < 0 || from >= _workspaces.length || to >= _workspaces.length) {
      return;
    }
    final selected = _workspaces[_selectedIndex];
    final item = _workspaces.removeAt(from);
    _workspaces.insert(to, item);
    _selectedIndex = _workspaces.indexOf(selected);
    notifyListeners();
  }

  void setBarExpanded(bool expanded) {
    if(_barExpanded == expanded) {
      return;
    }
    _barExpanded = expanded;
    final prefs = AnalystDatabase().getPreferencesSync();
    prefs.workspaceBarExpanded = expanded;
    AnalystDatabase().savePreferencesSync(prefs);
    notifyListeners();
  }

  void toggleBarExpanded() => setBarExpanded(!_barExpanded);

  Workspace _createWorkspace() => Workspace();

  void _attach(Workspace workspace) {
    _workspaces.add(workspace);
  }

  void _detach(Workspace workspace) {
  }

  @override
  void dispose() {
    for(var workspace in _workspaces) {
      _detach(workspace);
      workspace.dispose();
    }
    _workspaces.clear();
    super.dispose();
  }
}
