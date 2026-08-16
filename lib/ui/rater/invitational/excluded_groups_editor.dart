/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "package:flutter/material.dart";
import "package:shooting_sports_analyst/data/database/schema/ratings.dart";
import "package:shooting_sports_analyst/data/ranking/invitational/invitation_match.dart";
import "package:shooting_sports_analyst/data/ranking/invitational/invitational_invite_config.dart";
import "package:shooting_sports_analyst/ui/rater/invitational/match_source_id_chips.dart";

class ExcludedGroupsEditor extends StatefulWidget {
  const ExcludedGroupsEditor({
    super.key,
    required this.rule,
    required this.projectGroups,
    required this.matchPointers,
    required this.onChanged,
    required this.onDelete,
  });

  final ExcludedGroupsRule rule;
  final List<RatingGroup> projectGroups;
  final List<MatchPointer> matchPointers;
  final VoidCallback onChanged;
  final VoidCallback onDelete;

  @override
  State<ExcludedGroupsEditor> createState() => _ExcludedGroupsEditorState();
}

class _ExcludedGroupsEditorState extends State<ExcludedGroupsEditor> {
  late TextEditingController _patternsController;

  @override
  void initState() {
    super.initState();
    _patternsController = TextEditingController(
      text: widget.rule.namePatterns.map((p) => p.pattern).join("\n"),
    );
  }

  @override
  void dispose() {
    _patternsController.dispose();
    super.dispose();
  }

  void _applyPatterns(String text) {
    final lines = text.split("\n").map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    final parsed = <RegExp>[];
    for(final line in lines) {
      try {
        parsed.add(RegExp(line));
      }
      catch(_) {
        return;
      }
    }
    widget.rule.namePatterns = parsed;
    widget.onChanged();
  }

  bool _groupSelected(RatingGroup group) {
    for(final key in widget.rule.groupKeys) {
      final found = findRatingGroup(widget.projectGroups, key);
      if(found != null && found.uuid == group.uuid) {
        return true;
      }
    }
    return widget.rule.groupKeys.contains(group.uuid) || widget.rule.groupKeys.contains(group.name);
  }

  @override
  Widget build(BuildContext context) {
    final unresolved = widget.rule.groupKeys.where((key) => findRatingGroup(widget.projectGroups, key) == null).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text("Exclude Groups For Matching Matches", style: Theme.of(context).textTheme.titleSmall),
                ),
                IconButton(
                  tooltip: "Remove rule",
                  icon: const Icon(Icons.delete_outline),
                  onPressed: widget.onDelete,
                ),
              ],
            ),
            Wrap(
              spacing: 8,
              children: [
                for(final group in widget.projectGroups)
                  FilterChip(
                    label: Text(group.uiLabel),
                    selected: _groupSelected(group),
                    onSelected: (selected) {
                      if(selected) {
                        if(!_groupSelected(group)) {
                          widget.rule.groupKeys.add(group.uuid);
                        }
                      }
                      else {
                        widget.rule.groupKeys.removeWhere((key) {
                          final found = findRatingGroup(widget.projectGroups, key);
                          return key == group.uuid || key == group.name || found?.uuid == group.uuid;
                        });
                      }
                      widget.onChanged();
                      setState(() {});
                    },
                  ),
              ],
            ),
            if(unresolved.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text("Unresolved groups: ${unresolved.join(", ")}", style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 12),
            Text("Matches", style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            MatchSourceIdChips(
              sourceIds: widget.rule.sourceIds,
              matchPointers: widget.matchPointers,
              onChanged: (ids) {
                widget.rule.sourceIds
                  ..clear()
                  ..addAll(ids);
                widget.onChanged();
                setState(() {});
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _patternsController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: "Match name patterns",
                hintText: "One regex per line. Any pattern matches.",
                border: OutlineInputBorder(),
              ),
              onChanged: _applyPatterns,
            ),
          ],
        ),
      ),
    );
  }
}
