/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "package:flutter/material.dart";
import "package:shooting_sports_analyst/data/ranking/invitational/invitation_match.dart";
import "package:shooting_sports_analyst/data/database/schema/ratings.dart";
import "package:shooting_sports_analyst/ui/rater/invitational/match_source_id_chips.dart";
import "package:shooting_sports_analyst/ui/rater/invitational/numeric_fields.dart";
import "package:shooting_sports_analyst/util.dart";

class InvitationMatchEditor extends StatefulWidget {
  const InvitationMatchEditor({
    super.key,
    required this.rule,
    required this.matchPointers,
    required this.onChanged,
    required this.onDelete,
  });

  final InvitationMatch rule;
  final List<MatchPointer> matchPointers;
  final VoidCallback onChanged;
  final VoidCallback onDelete;

  @override
  State<InvitationMatchEditor> createState() => _InvitationMatchEditorState();
}

class _InvitationMatchEditorState extends State<InvitationMatchEditor> {
  late TextEditingController _includeController;
  late TextEditingController _excludeController;

  @override
  void initState() {
    super.initState();
    _includeController = TextEditingController(text: _patternsToText(widget.rule.includePatterns));
    _excludeController = TextEditingController(text: _patternsToText(widget.rule.negativePatterns));
  }

  @override
  void dispose() {
    _includeController.dispose();
    _excludeController.dispose();
    super.dispose();
  }

  String _patternsToText(List<RegExp> patterns) {
    return patterns.map((p) => p.pattern).join("\n");
  }

  List<RegExp>? _parsePatterns(String text) {
    final lines = text.split("\n").map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    final parsed = <RegExp>[];
    for(final line in lines) {
      try {
        parsed.add(RegExp(line));
      }
      catch(_) {
        return null;
      }
    }
    return parsed;
  }

  void _applyInclude(String text) {
    final parsed = _parsePatterns(text);
    if(parsed == null) {
      return;
    }
    widget.rule.namePattern = parsed.isNotEmpty ? parsed.first : null;
    widget.rule.additionalPatterns = parsed.skip(1).toList();
    widget.onChanged();
  }

  void _applyExclude(String text) {
    final parsed = _parsePatterns(text);
    if(parsed == null) {
      return;
    }
    widget.rule.negativePatterns = parsed;
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final rule = widget.rule;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownMenu<InvitationMatchType>(
                    key: ValueKey(rule.type),
                    label: const Text("Type"),
                    expandedInsets: EdgeInsets.zero,
                    initialSelection: rule.type,
                    requestFocusOnTap: false,
                    dropdownMenuEntries: [
                      for(final type in InvitationMatchType.values)
                        DropdownMenuEntry(value: type, label: type.label),
                    ],
                    onSelected: (type) {
                      if(type == null || type == rule.type) {
                        return;
                      }
                      final replacement = rule.withType(type);
                      rule.topN = replacement.topN;
                      rule.aboveNPercent = replacement.aboveNPercent;
                      rule.either = replacement.either;
                      rule.both = replacement.both;
                      widget.onChanged();
                      setState(() {});
                    },
                  ),
                ),
                const SizedBox(width: 12),
                if(rule.type != InvitationMatchType.aboveNPercent)
                  IntTextField(
                    value: rule.topN ?? 1,
                    label: "Top N",
                    onChanged: (value) {
                      rule.topN = value;
                      widget.onChanged();
                    },
                  ),
                if(rule.type != InvitationMatchType.topN) ...[
                  const SizedBox(width: 12),
                  DoubleTextField(
                    value: (rule.aboveNPercent ?? 0.9) * 100,
                    label: "Above %",
                    width: 90,
                    onChanged: (value) {
                      rule.aboveNPercent = value / 100.0;
                      widget.onChanged();
                    },
                  ),
                ],
                const SizedBox(width: 12),
                IntTextField(
                  value: rule.priority,
                  label: "Priority",
                  onChanged: (value) {
                    rule.priority = value;
                    widget.onChanged();
                  },
                ),
                const SizedBox(width: 12),
                IntTextField(
                  value: rule.minimumCompetitors,
                  label: "Min. Competitors",
                  width: 110,
                  onChanged: (value) {
                    rule.minimumCompetitors = value;
                    widget.onChanged();
                  },
                ),
                IconButton(
                  tooltip: "Remove rule",
                  icon: const Icon(Icons.delete_outline),
                  onPressed: widget.onDelete,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(rule.afterDate != null
                    ? "After ${programmerYmdFormat.format(rule.afterDate!)}"
                    : "No after-date filter"),
                const SizedBox(width: 8),
                TextButton(
                  child: const Text("SET DATE"),
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: rule.afterDate ?? DateTime.now(),
                      firstDate: DateTime(2010),
                      lastDate: DateTime.now(),
                    );
                    if(picked != null) {
                      rule.afterDate = picked;
                      widget.onChanged();
                      setState(() {});
                    }
                  },
                ),
                if(rule.afterDate != null)
                  TextButton(
                    child: const Text("CLEAR"),
                    onPressed: () {
                      rule.afterDate = null;
                      widget.onChanged();
                      setState(() {});
                    },
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text("Matches", style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            MatchSourceIdChips(
              sourceIds: rule.sourceIds,
              matchPointers: widget.matchPointers,
              onChanged: (ids) {
                rule.sourceIds
                  ..clear()
                  ..addAll(ids);
                widget.onChanged();
                setState(() {});
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _includeController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: "Include name patterns",
                hintText: "One regex per line. All must match.",
                border: OutlineInputBorder(),
              ),
              onChanged: _applyInclude,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _excludeController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: "Exclude name patterns",
                hintText: "One regex per line. Any match excludes.",
                border: OutlineInputBorder(),
              ),
              onChanged: _applyExclude,
            ),
          ],
        ),
      ),
    );
  }
}
