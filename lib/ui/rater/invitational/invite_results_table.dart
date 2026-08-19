/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "package:collection/collection.dart";
import "package:flutter/material.dart";
import "package:shooting_sports_analyst/data/database/schema/ratings.dart";
import "package:shooting_sports_analyst/data/ranking/interface/rating_data_source.dart";
import "package:shooting_sports_analyst/data/ranking/invitational/invitation.dart";
import "package:shooting_sports_analyst/data/ranking/invitational/invitational_invite_engine.dart";
import "package:shooting_sports_analyst/ui/colors.dart";
import "package:shooting_sports_analyst/ui/rater/invitational/invitation_detail_dialog.dart";
import "package:shooting_sports_analyst/ui/widget/score_row.dart";
import "package:shooting_sports_analyst/util.dart";

class InviteResultsTable extends StatefulWidget {
  const InviteResultsTable({super.key, required this.result, required this.dataSource});

  final InvitationalInviteResult result;
  final RatingDataSource dataSource;

  @override
  State<InviteResultsTable> createState() => _InviteResultsTableState();
}

class _InviteResultsTableState extends State<InviteResultsTable> {
  _TernaryFilter _fallback = _TernaryFilter.any;
  _TernaryFilter _lady = _TernaryFilter.any;
  _TernaryFilter _junior = _TernaryFilter.any;
  _TernaryFilter _senior = _TernaryFilter.any;
  _TernaryFilter _reserved = _TernaryFilter.any;

  InvitationalInviteResult get result => widget.result;

  bool get _hasActiveFilters =>
    _fallback != _TernaryFilter.any ||
    _lady != _TernaryFilter.any ||
    _junior != _TernaryFilter.any ||
    _senior != _TernaryFilter.any ||
    _reserved != _TernaryFilter.any;

  bool get _filteredEmpty {
    for(final group in result.groups) {
      final invitations = result.invitationsByGroup[group] ?? [];
      if(invitations.any(_matches)) {
        return false;
      }
    }
    return true;
  }

  @override
  void didUpdateWidget(InviteResultsTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if(!result.ladySlots) {
      _lady = _TernaryFilter.any;
    }
    if(!result.juniorSlots) {
      _junior = _TernaryFilter.any;
    }
    if(!result.seniorSlots) {
      _senior = _TernaryFilter.any;
    }
    if(!result.anyReservedSlots) {
      _reserved = _TernaryFilter.any;
    }
  }

  void _resetFilters() {
    setState(() {
      _fallback = _TernaryFilter.any;
      _lady = _TernaryFilter.any;
      _junior = _TernaryFilter.any;
      _senior = _TernaryFilter.any;
      _reserved = _TernaryFilter.any;
    });
  }

  bool _matchesTernary(_TernaryFilter filter, bool value) {
    return switch(filter) {
      _TernaryFilter.any => true,
      _TernaryFilter.yes => value,
      _TernaryFilter.no => !value,
    };
  }

  bool _matches(Invitation invitation) {
    if(!_matchesTernary(_fallback, invitation.fallbackSlot)) {
      return false;
    }
    if(!_matchesTernary(_lady, invitation.rating.female)) {
      return false;
    }
    if(!_matchesTernary(_junior, invitation.rating.ageCategory?.isJunior == true)) {
      return false;
    }
    if(!_matchesTernary(_senior, invitation.rating.ageCategory?.isSenior == true)) {
      return false;
    }
    if(!_matchesTernary(_reserved, invitation.reservedSlot)) {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    if(result.invitations.isEmpty) {
      return const Center(child: Text("No invitations generated."));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text("Show", style: Theme.of(context).textTheme.titleSmall),
              _TernaryFilterMenu(
                label: "Fallback",
                value: _fallback,
                onChanged: (value) => setState(() => _fallback = value),
              ),
              if(result.ladySlots)
                _TernaryFilterMenu(
                  label: "Lady",
                  value: _lady,
                  onChanged: (value) => setState(() => _lady = value),
                ),
              if(result.juniorSlots)
                _TernaryFilterMenu(
                  label: "Junior",
                  value: _junior,
                  onChanged: (value) => setState(() => _junior = value),
                ),
              if(result.seniorSlots)
                _TernaryFilterMenu(
                  label: "Senior",
                  value: _senior,
                  onChanged: (value) => setState(() => _senior = value),
                ),
              if(result.anyReservedSlots)
                _TernaryFilterMenu(
                  label: "Reserved",
                  value: _reserved,
                  onChanged: (value) => setState(() => _reserved = value),
                ),
              IconButton(
                tooltip: "Reset Filters",
                icon: const Icon(Icons.refresh),
                onPressed: _hasActiveFilters ? _resetFilters : null,
              ),
            ],
          ),
        ),
        Expanded(
          child: _filteredEmpty
              ? const Center(child: Text("No invitations match the current filters."))
              : ListView(
                  children: [
                    for(final group in result.groups)
                      ..._groupSection(context, group),
                  ],
                ),
        ),
      ],
    );
  }

  List<Widget> _groupSection(BuildContext context, RatingGroup group) {
    final invitations = result.invitationsByGroup[group] ?? [];
    final filtered = invitations.where(_matches).toList();
    if(filtered.isEmpty) {
      return [];
    }

    final ladyCount = result.ladyInvitationsByGroup[group]?.length ?? 0;
    final juniorCount = result.juniorInvitationsByGroup[group]?.length ?? 0;
    final seniorCount = result.seniorInvitationsByGroup[group]?.length ?? 0;
    final categoryBits = <String>[
      if(result.ladySlots) "$ladyCount lady",
      if(result.juniorSlots) "$juniorCount junior",
      if(result.seniorSlots) "$seniorCount senior",
    ];
    final countLabel = _hasActiveFilters
        ? "${filtered.length} of ${invitations.length} invitations"
        : "${invitations.length} invitations";
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text(
          "${group.name}: $countLabel"
          "${categoryBits.isNotEmpty ? " (${categoryBits.join(", ")})" : ""}"
          "  ${result.filledSlotsByGroup[group] ?? 0}/${result.maximumSlotsByGroup[group] ?? 0} filled",
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
      _headerRow(context),
      for(final (index, invitation) in filtered.indexed)
        _invitationRow(context, invitation, index),
    ];
  }

  Widget _headerRow(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
            bottom: BorderSide(color: ThemeColors.onBackgroundColor(context))
        ),
        color: ThemeColors.backgroundColor(context),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            const Expanded(flex: 1, child: Text("Fallback")),
            if(result.ladySlots) const Expanded(flex: 1, child: Text("Lady")),
            if(result.juniorSlots) const Expanded(flex: 1, child: Text("Junior")),
            if(result.seniorSlots) const Expanded(flex: 1, child: Text("Senior")),
            if(result.anyReservedSlots) const Expanded(flex: 1, child: Text("Reserved")),
            const Expanded(flex: 2, child: Text("Member#")),
            const Expanded(flex: 4, child: Text("Name")),
            if(result.includeEmails) const Expanded(flex: 3, child: Text("Email")),
            const Expanded(flex: 2, child: Text("Group")),
            const Expanded(flex: 2, child: Text("Rating")),
            const Expanded(flex: 4, child: Text("Match")),
            const Expanded(flex: 2, child: Text("Date")),
            const Expanded(flex: 1, child: Text("Place")),
            const Expanded(flex: 1, child: Text("%")),
          ],
        ),
      )
    );
  }

  Widget _invitationRow(BuildContext context, Invitation invitation, int index) {
    final match = invitation.earnedAtMatches.firstOrNull;
    return GestureDetector(
      onTap: () {
        InvitationDetailDialog.show(
          context,
          invitation: invitation,
          combinedScoring: widget.result.config.combinedScoringForMultiDivisionGroups,
          result: result,
          dataSource: widget.dataSource,
        );
      },
      child: ScoreRow(
        index: index,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              Expanded(flex: 1, child: Text(invitation.fallbackSlot ? "Y" : "N")),
              if(result.ladySlots) Expanded(flex: 1, child: Text(invitation.rating.female ? "Y" : "N")),
              if(result.juniorSlots) Expanded(flex: 1, child: Text(invitation.rating.ageCategory?.isJunior == true ? "Y" : "N")),
              if(result.seniorSlots) Expanded(flex: 1, child: Text(invitation.rating.ageCategory?.isSenior == true ? "Y" : "N")),
              if(result.anyReservedSlots) Expanded(flex: 1, child: Text(invitation.reservedSlot ? "Y" : "N")),
              Expanded(flex: 2, child: Text(invitation.rating.memberNumber)),
              Expanded(flex: 4, child: Text(invitation.rating.name, overflow: TextOverflow.ellipsis)),
              if(result.includeEmails) Expanded(flex: 3, child: Text(invitation.rating.email ?? "", overflow: TextOverflow.ellipsis)),
              Expanded(flex: 2, child: Text(invitation.groups.map((g) => g.uiLabel).sorted().join("|"), overflow: TextOverflow.ellipsis)),
              Expanded(
                flex: 2,
                child: Text(invitation.earnedAtMatches.isNotEmpty ? "Match slot" : invitation.rating.formattedRating),
              ),
              Expanded(flex: 4, child: Text(match?.name ?? "Elo slot", overflow: TextOverflow.ellipsis)),
              Expanded(flex: 2, child: Text(match != null ? programmerYmdFormat.format(match.date) : "Elo slot")),
              Expanded(flex: 1, child: Text("${invitation.relativeMatchScores.firstOrNull?.place ?? "Elo slot"}")),
              Expanded(flex: 1, child: Text(invitation.relativeMatchScores.firstOrNull?.ratio.asPercentage() ?? "Elo slot")),
            ],
          ),
        ),
      ),
    );
  }
}

enum _TernaryFilter {
  any,
  yes,
  no;

  String get label => switch(this) {
    any => "Any",
    yes => "Yes",
    no => "No",
  };
}

class _TernaryFilterMenu extends StatelessWidget {
  const _TernaryFilterMenu({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final _TernaryFilter value;
  final ValueChanged<_TernaryFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownMenu<_TernaryFilter>(
      key: ValueKey("$label-$value"),
      label: Text(label),
      initialSelection: value,
      width: 140,
      requestFocusOnTap: false,
      dropdownMenuEntries: [
        for(final filter in _TernaryFilter.values)
          DropdownMenuEntry(value: filter, label: filter.label),
      ],
      onSelected: (selected) {
        if(selected != null) {
          onChanged(selected);
        }
      },
    );
  }
}
