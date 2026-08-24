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
    required this.ladySlots,
    required this.juniorSlots,
    required this.seniorSlots,
    required this.onChanged,
    required this.onDelete,
  });

  final InvitationMatch rule;
  final List<MatchPointer> matchPointers;
  final bool ladySlots;
  final bool juniorSlots;
  final bool seniorSlots;
  final VoidCallback onChanged;
  final VoidCallback onDelete;

  @override
  State<InvitationMatchEditor> createState() => _InvitationMatchEditorState();
}

class _InvitationMatchEditorState extends State<InvitationMatchEditor> {
  late TextEditingController _nameController;
  late TextEditingController _includeController;
  late TextEditingController _excludeController;
  bool _expanded = true;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.rule.name ?? "");
    _includeController = TextEditingController(text: _patternsToText(widget.rule.includePatterns));
    _excludeController = TextEditingController(text: _patternsToText(widget.rule.negativePatterns));
  }

  @override
  void dispose() {
    _nameController.dispose();
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

  bool _scopeEnabled(InvitationMatchScope scope) {
    return switch(scope) {
      InvitationMatchScope.general || InvitationMatchScope.all => true,
      InvitationMatchScope.categories => widget.ladySlots || widget.juniorSlots || widget.seniorSlots,
      InvitationMatchScope.lady => widget.ladySlots,
      InvitationMatchScope.junior => widget.juniorSlots,
      InvitationMatchScope.senior => widget.seniorSlots,
    };
  }

  String _scopeHint(InvitationMatchScope scope) {
    if(_scopeEnabled(scope)) {
      return scope.label;
    }
    return "${scope.label} (enable reserved slots)";
  }

  String _headerSubtitle(InvitationMatch rule) {
    final bits = <String>[
      rule.scope.label,
      if(rule.name?.trim().isNotEmpty == true) rule.ruleSummary,
      "Priority ${rule.priority}",
    ];
    return bits.join(" · ");
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
                IconButton(
                  tooltip: _expanded ? "Collapse" : "Expand",
                  icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                  onPressed: () => setState(() => _expanded = !_expanded),
                ),
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _expanded = !_expanded),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            rule.displayLabel,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          if(!_expanded)
                            Text(
                              _headerSubtitle(rule),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: "Remove rule",
                  icon: const Icon(Icons.delete_outline),
                  onPressed: widget.onDelete,
                ),
              ],
            ),
            if(_expanded) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: "Name",
                  hintText: "Optional short label",
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) {
                  final trimmed = value.trim();
                  rule.name = trimmed.isEmpty ? null : trimmed;
                  widget.onChanged();
                  setState(() {});
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownMenu<InvitationMatchScope>(
                      key: ValueKey("scope-${rule.scope}"),
                      label: const Text("Scope"),
                      expandedInsets: EdgeInsets.zero,
                      initialSelection: rule.scope,
                      requestFocusOnTap: false,
                      dropdownMenuEntries: [
                        for(final scope in InvitationMatchScope.values)
                          DropdownMenuEntry(
                            value: scope,
                            label: _scopeHint(scope),
                            enabled: _scopeEnabled(scope),
                          ),
                      ],
                      onSelected: (scope) {
                        if(scope == null || scope == rule.scope || !_scopeEnabled(scope)) {
                          return;
                        }
                        rule.scope = scope;
                        widget.onChanged();
                        setState(() {});
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
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
          ],
        ),
      ),
    );
  }
}
