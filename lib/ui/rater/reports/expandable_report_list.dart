/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shooting_sports_analyst/ui/rater/rating_report_ui.dart';
import 'package:shooting_sports_analyst/ui/rater/reports/report_view.dart';

class ExpandableReportList extends StatelessWidget {
  const ExpandableReportList({super.key});

  @override
  Widget build(BuildContext context) {
    var filteredReports = Provider.of<ReportViewModel>(context).filteredReports;
    return ListView.builder(
      itemCount: filteredReports.length,
      itemBuilder: (context, index) {
        var report = filteredReports[index];
        return ExpansionTile(
          title: Text(report.uiTitle),
          key: PageStorageKey(index),
          subtitle: report.uiSubtitle != null ? Text(report.uiSubtitle!) : null,
          leading: Icon(report.severity.uiIcon, color: report.severity.uiColor),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: report.expandedUi(context),
              ),
            ),
          ],
        );
      },
    );
  }
}
