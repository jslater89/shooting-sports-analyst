/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/rating_report.dart';
import 'package:shooting_sports_analyst/data/help/rating_reports_help.dart';
import 'package:shooting_sports_analyst/data/ranking/interface/rating_data_source.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/ui/rater/reports/report_view.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/help/help_dialog.dart';
import 'package:shooting_sports_analyst/util.dart';

SSALogger _log = SSALogger("ReportDialog");

class ReportDialog extends StatefulWidget {
  const ReportDialog({super.key, required this.dataSource});

  final RatingDataSource dataSource;

  @override
  State<ReportDialog> createState() => _ReportDialogState();

  static Future<void> show(BuildContext context, RatingDataSource dataSource) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) => ReportDialog(dataSource: dataSource),
    );
  }
}

class _ReportDialogState extends State<ReportDialog> {

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    _allReports = await widget.dataSource.getAllReports().unwrap();
    _recentReports = await widget.dataSource.getRecentReports().unwrap();

    _log.i("Fetched ${_allReports!.length} reports (${_recentReports!.length} recent reports)");

    setState(() {});
  }

  List<RatingReport>? _allReports;
  List<RatingReport>? _recentReports;

  @override
  Widget build(BuildContext context) {
    if(_allReports == null || _recentReports == null) {
      return AlertDialog(
        title: Row(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text("Reports"),
            Row(
              children: [
                HelpButton(helpTopicId: ratingReportsHelpId),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ],
        ),
        content: SizedBox(
          width: 1000,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    return AlertDialog(
      title: Row(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text("Reports"),
            Row(
              children: [
                HelpButton(helpTopicId: ratingReportsHelpId),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ],
        ),
      content: SizedBox(
        width: 1000,
        child: RatingReportView(allReports: _allReports!, recentReports: _recentReports!),
      ),
    );
  }
}
