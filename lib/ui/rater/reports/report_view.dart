/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/rating_report.dart';
import 'package:shooting_sports_analyst/ui/rater/reports/expandable_report_list.dart';
import 'package:shooting_sports_analyst/ui/rater/reports/filter_bar.dart';

class RatingReportView extends StatefulWidget {
  const RatingReportView({super.key, required this.allReports, required this.recentReports});

  final List<RatingReport> allReports;
  final List<RatingReport> recentReports;

  @override
  State<RatingReportView> createState() => _RatingReportViewState();
}

class _RatingReportViewState extends State<RatingReportView> {
  late ReportViewModel filterModel;

  @override
  void initState() {
    super.initState();
    filterModel = ReportViewModel(
      groupNames: widget.allReports.map((e) => e.ratingGroupName).toSet().toList(),
      allReports: widget.allReports,
      recentReports: widget.recentReports,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: filterModel,
      child: Column(
        children: [
          ReportFilterBar(),
          Expanded(child: ExpandableReportList()),
        ],
      ),
    );
  }
}

class ReportViewModel extends ChangeNotifier {
  ReportViewModel({required this.groupNames, required this.allReports, required this.recentReports}) :
    _selectedTypes = [...RatingReportType.values],
    _selectedGroups = [...groupNames],
    _selectedSeverity = RatingReportSeverity.info,
    _filteredReports = [...allReports] {
      _applyFilters(); // for sort
    }

  final List<String> groupNames;
  final List<RatingReport> allReports;
  final List<RatingReport> recentReports;
  
  List<RatingReport> get filteredReports => _filteredReports;
  List<RatingReport> _filteredReports;

  ReportMode _mode = ReportMode.recent;
  ReportMode get mode => _mode;

  void setMode(ReportMode mode) {
    _mode = mode;
    _applyFilters();
    notifyListeners();
  }

  List<RatingReport> get reports => _mode == ReportMode.all ? allReports : recentReports;

  void _applyFilters() {
    _filteredReports = reports.where((report) {
      return selectedTypes.contains(report.type) &&
          selectedGroups.contains(report.ratingGroupName) &&
          report.severity.index >= selectedSeverity.index;
    }).toList();
    _filteredReports.sort((a, b) {
      if(a.severity != b.severity) {
        return b.severity.index.compareTo(a.severity.index);
      }
      return a.uiTitle.compareTo(b.uiTitle);
    });
  }

  void _filtersChanged() {
    _applyFilters();
    notifyListeners();
  }

  List<RatingReportType> _selectedTypes;
  List<RatingReportType> get selectedTypes => _selectedTypes;

  void addType(RatingReportType type) {
    _selectedTypes.add(type);
    _filtersChanged();
  }

  void removeType(RatingReportType type) {
    _selectedTypes.remove(type);
    _filtersChanged();
  }

  void setTypes(List<RatingReportType> types) {
    _selectedTypes = types;
    _filtersChanged();
  }

  void allTypes() {
    _selectedTypes = [...RatingReportType.values];
    _filtersChanged();
  }

  List<String> _selectedGroups;
  List<String> get selectedGroups => _selectedGroups;

  void addGroup(String group) {
    _selectedGroups.add(group);
    _filtersChanged();
  }

  void removeGroup(String group) {
    _selectedGroups.remove(group);
    _filtersChanged();
  }

  void setGroups(List<String> groups) {
    _selectedGroups = groups;
    _filtersChanged();
  }

  void allGroups() {
    _selectedGroups = [...groupNames];
    _filtersChanged();
  }

  RatingReportSeverity _selectedSeverity;
  RatingReportSeverity get selectedSeverity => _selectedSeverity;

  void setSeverity(RatingReportSeverity severity) {
    _selectedSeverity = severity;
    _filtersChanged();
  }
}

enum ReportMode {
  all,
  recent;

  String get uiLabel {
    switch(this) {
      case ReportMode.all:
        return "All";
      case ReportMode.recent:
        return "Last append";
    }
  }
}