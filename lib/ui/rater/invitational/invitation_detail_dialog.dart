/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "package:collection/collection.dart";
import "package:flutter/material.dart";
import "package:shooting_sports_analyst/config/config.dart";
import "package:shooting_sports_analyst/data/ranking/interface/rating_data_source.dart";
import "package:shooting_sports_analyst/data/ranking/invitational/invitation.dart";
import "package:shooting_sports_analyst/data/ranking/invitational/invitation_match.dart";
import "package:shooting_sports_analyst/data/ranking/invitational/invitational_invite_engine.dart";
import "package:shooting_sports_analyst/data/sport/model.dart";
import "package:shooting_sports_analyst/data/sport/shooter/filter_set.dart";
import "package:shooting_sports_analyst/ui/rater/shooter_stats_dialog.dart";
import "package:shooting_sports_analyst/ui/result_page.dart";
import "package:shooting_sports_analyst/ui/widget/clickable_link.dart";
import "package:shooting_sports_analyst/util.dart";

class InvitationDetailDialog extends StatelessWidget {
  const InvitationDetailDialog({
    super.key,
    required this.invitation,
    required this.combinedScoring,
    required this.result,
    required this.dataSource,
  });

  final Invitation invitation;
  final bool combinedScoring;
  final InvitationalInviteResult result;
  final RatingDataSource dataSource;

  /// Show the dialog.
  ///
  /// [combinedScoring] indicates whether the invitation was generated with combined scoring for multi-division groups,
  /// and tells the dialog whether to launch match scores in a group-combined or per-division view.
  static Future<void> show(
    BuildContext context, {
    required Invitation invitation,
    required bool combinedScoring,
    required InvitationalInviteResult result,
    required RatingDataSource dataSource,
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) => InvitationDetailDialog(
        invitation: invitation,
        combinedScoring: combinedScoring,
        result: result,
        dataSource: dataSource,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uiScaleFactor = ChangeNotifierConfigLoader().uiConfig.uiScaleFactor;
    final matchQualifications = invitation.deduplicatedMatchQualifications;
    final ratingQualifications = invitation.ratingQualifications
        .sorted((a, b) => a.group.uiLabel.compareTo(b.group.uiLabel));
    final invitedGroups = invitation.groups.sorted((a, b) => a.uiLabel.compareTo(b.uiLabel));

    return AlertDialog(
      title: Row(
        children: [
          Expanded(
            child: Text(invitation.rating.name, overflow: TextOverflow.ellipsis),
          ),
          Tooltip(
            message: "Show this competitor's rating history",
            child: IconButton(
              icon: const Icon(Icons.auto_graph),
              onPressed: () {
                ShooterStatsDialog.show(
                  context,
                  invitation.rating,
                  match: matchQualifications.firstOrNull?.match,
                  ratings: dataSource,
                  showDivisions: invitation.groups.length > 1,
                );
              },
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 900 * uiScaleFactor,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _summarySection(context, uiScaleFactor),
              SizedBox(height: 16 * uiScaleFactor),
              _sectionTitle(context, uiScaleFactor, "Invited groups"),
              _bodyText(context, uiScaleFactor, invitedGroups.map((g) => g.uiLabel).join(", ")),
              if(matchQualifications.isNotEmpty) ...[
                SizedBox(height: 16 * uiScaleFactor),
                _sectionTitle(context, uiScaleFactor, "Match qualifications"),
                _matchQualificationsTable(context, uiScaleFactor, combinedScoring, matchQualifications),
              ],
              if(ratingQualifications.isNotEmpty) ...[
                SizedBox(height: 16 * uiScaleFactor),
                _sectionTitle(context, uiScaleFactor, "Rating qualifications"),
                for(final qualification in ratingQualifications)
                  Padding(
                    padding: EdgeInsets.only(left: 8 * uiScaleFactor, top: 4 * uiScaleFactor),
                    child: Text(
                      "• ${qualification.group.uiLabel} (${qualification.source.label})",
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
              ],
              if(matchQualifications.isEmpty && ratingQualifications.isEmpty)
                Padding(
                  padding: EdgeInsets.only(top: 8 * uiScaleFactor),
                  child: Text(
                    "No qualification details recorded.",
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text("CLOSE"),
        ),
      ],
    );
  }

  Widget _summarySection(BuildContext context, double uiScaleFactor) {
    final statusBits = <String>[
      invitation.fallbackSlot ? "Fallback" : "Main slot",
      if(result.anyReservedSlots && invitation.reservedSlot) "Reserved",
      if(result.ladySlots && invitation.rating.female) "Lady",
      if(result.juniorSlots && invitation.rating.ageCategory?.isJunior == true) "Junior",
      if(result.seniorSlots && invitation.rating.ageCategory?.isSenior == true) "Senior",
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _detailRow(context, uiScaleFactor, "Member #", invitation.rating.memberNumber),
        if(result.includeEmails && (invitation.rating.email?.isNotEmpty ?? false))
          _detailRow(context, uiScaleFactor, "Email", invitation.rating.email!),
        _detailRow(context, uiScaleFactor, "Rating", invitation.rating.formattedRating),
        _detailRow(context, uiScaleFactor, "Status", statusBits.join(", ")),
      ],
    );
  }

  Widget _matchQualificationsTable(
    BuildContext context,
    double uiScaleFactor,
    bool combinedScoring,
    List<InvitationMatchQualification> qualifications,
  ) {
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(1.4),
        1: FlexColumnWidth(1.2),
        2: FlexColumnWidth(1.0),
        3: FlexColumnWidth(2.4),
        4: FlexColumnWidth(1.0),
        5: FlexColumnWidth(1.4),
        6: FlexColumnWidth(0.6),
        7: FlexColumnWidth(0.7),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          children: [
            _tableHeader(context, uiScaleFactor, "Group"),
            _tableHeader(context, uiScaleFactor, "Division"),
            _tableHeader(context, uiScaleFactor, "Date"),
            _tableHeader(context, uiScaleFactor, "Match"),
            _tableHeader(context, uiScaleFactor, "Pass"),
            _tableHeader(context, uiScaleFactor, "Rule"),
            _tableHeader(context, uiScaleFactor, "Place", align: TextAlign.right),
            _tableHeader(context, uiScaleFactor, "%", align: TextAlign.right),
          ],
        ),
        for(final qualification in qualifications)
          TableRow(
            children: [
              _tableCell(context, uiScaleFactor, qualification.group.uiLabel),
              _tableCell(context, uiScaleFactor, qualification.score.shooter.division?.shortDisplayName ?? "—"),
              _tableCell(context, uiScaleFactor, programmerYmdFormat.format(qualification.match.date)),
              _tableMatchCell(context, uiScaleFactor, combinedScoring, qualification),
              _tableCell(context, uiScaleFactor, qualification.passCategory.label),
              _tableCell(context, uiScaleFactor, _criterionLabel(qualification.criterion)),
              _tableCell(context, uiScaleFactor, "${qualification.score.place}", align: TextAlign.right),
              _tableCell(context, uiScaleFactor, qualification.score.ratio.asPercentage(), align: TextAlign.right),
            ],
          ),
      ],
    );
  }

  Widget _sectionTitle(BuildContext context, double uiScaleFactor, String text) {
    return Padding(
      padding: EdgeInsets.only(bottom: 6 * uiScaleFactor),
      child: Text(text, style: Theme.of(context).textTheme.titleSmall),
    );
  }

  String _criterionLabel(InvitationMatch criterion) {
    final trimmed = criterion.name?.trim();
    if(trimmed != null && trimmed.isNotEmpty) {
      return "$trimmed (${criterion.ruleSummary})";
    }
    return criterion.ruleSummary;
  }

  Widget _bodyText(BuildContext context, double uiScaleFactor, String text) {
    return Padding(
      padding: EdgeInsets.only(left: 8 * uiScaleFactor),
      child: Text(text, style: Theme.of(context).textTheme.bodyLarge),
    );
  }

  Widget _detailRow(BuildContext context, double uiScaleFactor, String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 2 * uiScaleFactor),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
          Expanded(
            child: Text(value, style: Theme.of(context).textTheme.bodyLarge),
          ),
        ],
      ),
    );
  }

  Widget _tableMatchCell(BuildContext context, double uiScaleFactor, bool combinedScoring, InvitationMatchQualification qualification) {
    return Padding(
      padding: EdgeInsets.only(top: 6 * uiScaleFactor, bottom: 6 * uiScaleFactor, right: 8 * uiScaleFactor),
      child: ClickableLink(
        onTap: () => _launchMatchResults(
          context,
          match: qualification.match,
          divisions: combinedScoring ? qualification.group.divisions : [qualification.score.shooter.division!],
        ),
        child: Text(
          qualification.match.name,
          style: Theme.of(context).textTheme.bodyMedium,
          softWrap: true,
        ),
      ),
    );
  }

  void _launchMatchResults(
    BuildContext context, {
    required ShootingMatch match,
    List<Division>? divisions,
  }) {
    final filters = FilterSet(match.sport, empty: true)
      ..mode = FilterMode.or;
    if(divisions != null) {
      filters.divisions = FilterSet.divisionListToMap(match.sport, divisions);
    }

    Navigator.of(context).push(MaterialPageRoute(builder: (context) {
      return ResultPage(
        canonicalMatch: match,
        initialFilters: filters,
        allowWhatIf: false,
        ratings: dataSource,
      );
    }));
  }

  Widget _tableHeader(BuildContext context, double uiScaleFactor, String text, {TextAlign align = TextAlign.left}) {
    return Padding(
      padding: EdgeInsets.only(bottom: 6 * uiScaleFactor, right: 8 * uiScaleFactor),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge,
        textAlign: align,
      ),
    );
  }

  Widget _tableCell(BuildContext context, double uiScaleFactor, String text, {TextAlign align = TextAlign.left}) {
    return Padding(
      padding: EdgeInsets.only(top: 6 * uiScaleFactor, bottom: 6 * uiScaleFactor, right: 8 * uiScaleFactor),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodyMedium,
        textAlign: align,
      ),
    );
  }
}
