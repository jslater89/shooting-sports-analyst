/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shooting_sports_analyst/config/config.dart';
import 'package:shooting_sports_analyst/data/help/entries/workspaces_help.dart';
import 'package:shooting_sports_analyst/main.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/help/help_dialog.dart';
import 'package:shooting_sports_analyst/ui/workspace/workspace.dart';
import 'package:shooting_sports_analyst/ui/workspace/workspace_manager.dart';

/// Top-level chrome: collapsible workspace tabs over an [IndexedStack] of
/// nested navigators.
class WorkspaceShell extends StatelessWidget {
  const WorkspaceShell({super.key});

  @override
  Widget build(BuildContext context) {
    final manager = context.watch<WorkspaceManager>();
    final theme = Theme.of(context);
    final uiScaleFactor = ChangeNotifierConfigLoader().uiConfig.uiScaleFactor;
    final surface = theme.colorScheme.surface;
    final onSurface = theme.colorScheme.onSurface;

    return Column(
      children: [
        if(manager.barExpanded) _WorkspaceTabBar(manager: manager, uiScaleFactor: uiScaleFactor),
        _ChevronBar(
          expanded: manager.barExpanded,
          onTap: manager.toggleBarExpanded,
          color: surface,
          iconColor: onSurface.withValues(alpha: 0.55),
          borderColor: theme.dividerColor,
          uiScaleFactor: uiScaleFactor,
        ),
        Expanded(
          child: IndexedStack(
            index: manager.selectedIndex,
            sizing: StackFit.expand,
            children: [
              for(var workspace in manager.workspaces)
                _WorkspaceNavigator(
                  key: ObjectKey(workspace),
                  workspace: workspace,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ChevronBar extends StatelessWidget {
  const _ChevronBar({
    required this.expanded,
    required this.onTap,
    required this.color,
    required this.iconColor,
    required this.borderColor,
    required this.uiScaleFactor,
  });

  final bool expanded;
  final VoidCallback onTap;
  final Color color;
  final Color iconColor;
  final Color borderColor;
  final double uiScaleFactor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 16 * uiScaleFactor,
          width: double.infinity,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: borderColor),
            ),
          ),
          alignment: Alignment.center,
          child: Tooltip(
            message: expanded ? "Collapse workspace switcher" : "Expand workspace switcher",
            child: Icon(
              expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
              size: 14 * uiScaleFactor,
              color: iconColor,
            ),
          ),
        ),
      ),
    );
  }
}

class _WorkspaceTabBar extends StatefulWidget {
  const _WorkspaceTabBar({
    required this.manager,
    required this.uiScaleFactor,
  });

  final WorkspaceManager manager;
  final double uiScaleFactor;

  @override
  State<_WorkspaceTabBar> createState() => _WorkspaceTabBarState();
}

class _WorkspaceTabBarState extends State<_WorkspaceTabBar> with TickerProviderStateMixin {
  TabController? _controller;

  @override
  void initState() {
    super.initState();
    _syncController();
  }

  @override
  void didUpdateWidget(covariant _WorkspaceTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncController();
  }

  @override
  void dispose() {
    _controller?.removeListener(_onTabChanged);
    _controller?.dispose();
    super.dispose();
  }

  void _syncController() {
    final manager = widget.manager;
    final length = manager.workspaces.length;
    final index = manager.selectedIndex.clamp(0, length - 1);

    if(_controller == null || _controller!.length != length) {
      _controller?.removeListener(_onTabChanged);
      _controller?.dispose();
      _controller = TabController(
        length: length,
        vsync: this,
        initialIndex: index,
        animationDuration: Duration.zero,
      );
      _controller!.addListener(_onTabChanged);
      return;
    }

    if(_controller!.index != index && !_controller!.indexIsChanging) {
      _controller!.index = index;
    }
  }

  void _onTabChanged() {
    final controller = _controller;
    if(controller == null || controller.indexIsChanging) {
      return;
    }
    widget.manager.select(controller.index);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final manager = widget.manager;
    final uiScaleFactor = widget.uiScaleFactor;
    final controller = _controller!;

    return Material(
      color: theme.colorScheme.surface,
      child: Row(
        children: [
          HelpButton(
            helpTopicId: workspacesHelpId,
          ),
          if(manager.canAdd)
            IconButton(
              tooltip: "New workspace",
              icon: Icon(Icons.add),
              onPressed: manager.addWorkspace,
              visualDensity: VisualDensity.compact,
            ),
          Expanded(
            child: TabBar(
              controller: controller,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              indicatorColor: theme.colorScheme.primary,
              labelColor: theme.colorScheme.primary,
              tabs: [
                for(var i = 0; i < manager.workspaces.length; i++)
                  Tab(
                    height: 46 * uiScaleFactor,
                    child: _WorkspaceTab(
                      index: i,
                      workspace: manager.workspaces[i],
                      canReorder: manager.workspaces.length > 1,
                      canClose: manager.workspaces.length > 1,
                      uiScaleFactor: uiScaleFactor,
                      onClose: () => manager.closeWorkspace(i),
                      onReorder: manager.reorder,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkspaceTab extends StatelessWidget {
  const _WorkspaceTab({
    required this.index,
    required this.workspace,
    required this.canReorder,
    required this.canClose,
    required this.uiScaleFactor,
    required this.onClose,
    required this.onReorder,
  });

  final int index;
  final Workspace workspace;
  final bool canReorder;
  final bool canClose;
  final double uiScaleFactor;
  final VoidCallback onClose;
  final void Function(int from, int to) onReorder;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: workspace,
      builder: (context, _) {
        final title = workspace.tabTitle;
        final theme = Theme.of(context);
        final tabBody = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if(canReorder) ...[
              _TabDragHandle(
                index: index,
                title: title,
                uiScaleFactor: uiScaleFactor,
              ),
              SizedBox(width: 2 * uiScaleFactor),
            ],
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 320 * uiScaleFactor),
              child: Text(
                title,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if(canClose) ...[
              SizedBox(width: 4 * uiScaleFactor),
              SizedBox(
                width: 28 * uiScaleFactor,
                height: 28 * uiScaleFactor,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  iconSize: 16 * uiScaleFactor,
                  tooltip: "Close workspace",
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close),
                  onPressed: onClose,
                ),
              ),
            ],
          ],
        );

        if(!canReorder) {
          return tabBody;
        }

        return DragTarget<int>(
          onWillAcceptWithDetails: (details) => details.data != index,
          onAcceptWithDetails: (details) => onReorder(details.data, index),
          builder: (context, candidateData, rejectedData) {
            final from = candidateData.whereType<int>().firstOrNull;
            final showLeading = from != null && index < from;
            final showTrailing = from != null && index > from;
            final indicator = BorderSide(
              color: theme.colorScheme.primary,
              width: 2 * uiScaleFactor,
            );
            return AnimatedContainer(
              duration: Duration.zero,
              decoration: (showLeading || showTrailing)
                  ? BoxDecoration(
                      border: Border(
                        left: showLeading ? indicator : BorderSide.none,
                        right: showTrailing ? indicator : BorderSide.none,
                      ),
                    )
                  : null,
              child: tabBody,
            );
          },
        );
      },
    );
  }
}

class _TabDragHandle extends StatelessWidget {
  const _TabDragHandle({
    required this.index,
    required this.title,
    required this.uiScaleFactor,
  });

  final int index;
  final String title;
  final double uiScaleFactor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final handle = MouseRegion(
      cursor: SystemMouseCursors.grab,
      child: Icon(
        Icons.drag_indicator,
        size: 16 * uiScaleFactor,
        color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
      ),
    );

    return Tooltip(
      message: "Drag to reorder",
      child: Draggable<int>(
        data: index,
        feedback: Material(
          elevation: 4,
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 10 * uiScaleFactor,
              vertical: 8 * uiScaleFactor,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.drag_indicator, size: 16 * uiScaleFactor),
                SizedBox(width: 4 * uiScaleFactor),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: 320 * uiScaleFactor),
                  child: Text(
                    title,
                    style: theme.textTheme.bodyMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
        childWhenDragging: Opacity(
          opacity: 0.35,
          child: handle,
        ),
        child: handle,
      ),
    );
  }
}

class _WorkspaceNavigator extends StatelessWidget {
  const _WorkspaceNavigator({super.key, required this.workspace});

  final Workspace workspace;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: workspace,
      child: Navigator(
        key: workspace.navigatorKey,
        observers: [workspace.routeObserver],
        initialRoute: "/",
        onGenerateRoute: globals.router.generator,
      ),
    );
  }
}
