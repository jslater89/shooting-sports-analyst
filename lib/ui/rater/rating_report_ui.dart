/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/rating_report.dart';
import 'package:shooting_sports_analyst/util.dart';

extension RatingReportUiBuilder on RatingReport {
  List<Widget> expandedUi(BuildContext context) {
    return type.expandedFor(context, this);
  }
}

extension RatingReportTypeUiBuilder on RatingReportType{
  List<Widget> expandedFor(BuildContext context, RatingReport data) {
    switch(this) {
      case RatingReportType.stringDifferenceNameForSameNumber:
        var typedData = data.data as StringDifferenceNameForSameNumber;
        return [
          Text(
            "The following names appear in the dataset for ${typedData.number} and have high string difference, which may indicate "
            "that they are different competitors. If they are, and you can identify an additional member number belonging to one "
            "of them, you can correct this issue by adding a data entry fix. If they are not distinct individuals, no action is "
            "required, but you can use a competitor name alias to resolve this report on the next full calculation.\n\n"
            "Note that this check occurs before competitor deduplication, so reports of this type may include entries that "
            "were fixed during deduplication on this calculation run."
          ),
          SizedBox(height: 8),
          ...typedData.names.map((name) => Text(" • $name")),
        ];
      case RatingReportType.ratingMergeWithDualHistory:
        var typedData = data.data as RatingMergeWithDualHistory;
        return [
          Text(
            "Ratings corresponding to the following member numbers were merged as a result of a member number mapping, "
            "but more than one rating had history data at the time of the merge. A full recalculation may be required for "
            "accurate ratings."
          ),
          SizedBox(height: 8),
          ...typedData.memberNumbers.map((number) => Text(" • $number")),
        ];
      case RatingReportType.dataEntryFixLoop:
        var typedData = data.data as DataEntryFixLoop;
        return [
          Text(
            "The following numbers are part of a data entry fix loop: data entry fixes occur for each number in this list, "
            "to the next, then cycle back to the first. At least one data entry fix from this list should be removed.\n\n"
            "This may indicate a bug in the shooter deduplicator. Please report it on Discord or GitHub."
          ),
          SizedBox(height: 8),
          Text(typedData.numbers.join(" → ")),
        ];
      case RatingReportType.duplicateDataEntryFix:
        var typedData = data.data as DuplicateDataEntryFix;
        return [
          Text(
            "The deduplicator attempted to add the data entry fix below, which duplicates an existing data entry fix. "
            "This is a deduplicator bug. Please report it on Discord or GitHub, including the information below and "
            "an export of your project file."
          ),
          SizedBox(height: 8),
          Text("Deduplicator name: ${typedData.deduplicatorName}"),
          Text("Source number: ${typedData.sourceNumber}"),
          Text("Target number: ${typedData.targetNumber}"),
        ];
      case RatingReportType.duplicateBlacklistEntry:
        var typedData = data.data as DuplicateBlacklistEntry;
        return [
          Text(
            "The deduplicator attempted to add the blacklist entry below, which duplicates an existing entry. "
            "This is a deduplicator bug. Please report it on Discord or GitHub, including the information below and "
            "an export of your project file."
          ),
          SizedBox(height: 8),
          Text("Source number: ${typedData.sourceNumber}"),
          Text("Target number: ${typedData.targetNumber}"),
        ];
      case RatingReportType.duplicateUserMapping:
        var typedData = data.data as DuplicateUserMapping;
        return [
          Text(
            "The user mapping below duplicates an existing user mapping. This may be an issue with the import of a "
            "pre-8.0 project, or it may indicate a deduplicator bug. Please report it on Discord or GitHub, including "
            "the information below and an export of your project file."
          ),
          SizedBox(height: 8),
          Text("Source number: ${typedData.sourceNumber}"),
          Text("Target number: ${typedData.targetNumber}"),
        ];
      case RatingReportType.duplicateAutoMapping:
        var typedData = data.data as DuplicateAutoMapping;
        return [
          Text(
            "The auto mapping below duplicates an existing auto mapping. This may be an issue with the import of a "
            "pre-8.0 project, or it may indicate a deduplicator bug. Please report it on Discord or GitHub, including "
            "the information below and an export of your project file."
          ),
          SizedBox(height: 8),
          Text("Source numbers: ${typedData.sourceNumbers.join(", ")}"),
          Text("Target number: ${typedData.targetNumber}"),
        ];
      case RatingReportType.blacklistedMapping:
        var typedData = data.data as BlacklistedMapping;
        return [
          Text(
            "The mapping below was detected and/or appears in the project settings, but is also blacklisted. "
            "The mapping was not applied. Remove the blacklist entry or the mapping to suppress this message."
          ),
          SizedBox(height: 8),
          Text("Source number: ${typedData.sourceNumber}"),
          Text("Target number: ${typedData.targetNumber}"),
        ];
      case RatingReportType.fiftyPercentDnfs:
        var typedData = data.data as FiftyPercentDnfs;
        return [
          Text(
            "The match ${typedData.matchName} has a DNF rate of ${typedData.dnfRatio.asPercentage(decimals: 0)} "
            "(${typedData.dnfCount}/${typedData.competitorCount}) in ${typedData.ratingGroupName}. This may indicate "
            "either a bug with the scoring system, an issue with the match data, or simply a low-participation "
            "division with some no-shows."
          ),
        ];
    }
  }
}

extension RatingReportSeverityUi on RatingReportSeverity {
    IconData get uiIcon => switch(this) {
    RatingReportSeverity.info => Icons.info,
    RatingReportSeverity.warning => Icons.warning,
    RatingReportSeverity.severe => Icons.cancel,
  };

  Color get uiColor => switch(this) {
    RatingReportSeverity.info => Colors.blue.shade700,
    RatingReportSeverity.warning => Colors.yellow.shade700,
    RatingReportSeverity.severe => Colors.red.shade600,
  };
}
