/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "package:flutter/material.dart";
import "package:shooting_sports_analyst/data/database/schema/ratings.dart";
import "package:shooting_sports_analyst/ui/widget/dialog/match_pointer_chooser_dialog.dart";

class MatchSourceIdChips extends StatelessWidget {
  const MatchSourceIdChips({
    super.key,
    required this.sourceIds,
    required this.matchPointers,
    required this.onChanged,
  });

  final List<String> sourceIds;
  final List<MatchPointer> matchPointers;
  final ValueChanged<List<String>> onChanged;

  String _labelFor(String id) {
    for(final pointer in matchPointers) {
      if(pointer.sourceIds.contains(id)) {
        return pointer.name;
      }
    }
    return id;
  }

  Future<void> _addMatches(BuildContext context) async {
    final selected = await MatchPointerChooserDialog.showMultiple(
      context: context,
      matches: matchPointers,
      showIds: true,
      helpText: "Select matches from this project. Chosen matches are added to the current list.",
    );
    if(selected == null) {
      return;
    }
    final next = [...sourceIds];
    for(final pointer in selected) {
      for(final id in pointer.sourceIds) {
        if(!next.contains(id)) {
          next.add(id);
        }
      }
    }
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for(final id in sourceIds)
              InputChip(
                label: Text(_labelFor(id)),
                tooltip: id,
                onDeleted: () {
                  onChanged(sourceIds.where((existing) => existing != id).toList());
                },
              ),
            ActionChip(
              avatar: const Icon(Icons.add, size: 18),
              label: const Text("Add Matches"),
              onPressed: () => _addMatches(context),
            ),
          ],
        ),
      ],
    );
  }
}
