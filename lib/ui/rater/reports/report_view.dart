/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/rating_report.dart';
import 'package:shooting_sports_analyst/ui/rater/reports/expandable_report_list.dart';
import 'package:shooting_sports_analyst/ui/rater/reports/filter_bar.dart';
import 'package:shooting_sports_analyst/util.dart';

class RatingReportView extends StatefulWidget {
  const RatingReportView({super.key, required this.allReports, required this.recentReports, this.onFiltersChanged, this.initialFilters});

  final List<RatingReport> allReports;
  final List<RatingReport> recentReports;
  final void Function(ReportFilters filters)? onFiltersChanged;
  final ReportFilters? initialFilters;

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
    if(widget.initialFilters != null) {
      filterModel.setFilters(widget.initialFilters!);
    }
    filterModel.addListener(() {
      widget.onFiltersChanged?.call(filterModel._filters);
    });
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

class ReportFilters {
  ReportFilters({required this.mode, required this.selectedGroups, required this.selectedTypes, required this.selectedSeverity});

  ReportMode mode;
  List<String> selectedGroups;
  List<RatingReportType> selectedTypes;
  RatingReportSeverity selectedSeverity;

  factory ReportFilters.copy(ReportFilters other) {
    return ReportFilters(mode: other.mode, selectedGroups: other.selectedGroups, selectedTypes: other.selectedTypes, selectedSeverity: other.selectedSeverity);
  }
}

class ReportViewModel extends ChangeNotifier {
  ReportViewModel({required this.groupNames, required this.allReports, required this.recentReports, ReportFilters? filters}) :
    _filteredReports = [...allReports] {
      _filters = filters ?? ReportFilters(mode: ReportMode.recent, selectedGroups: [...groupNames], selectedTypes: [...RatingReportType.values], selectedSeverity: RatingReportSeverity.info);
      _applyFilters(); // for sort
    }

  final List<String> groupNames;
  final List<RatingReport> allReports;
  final List<RatingReport> recentReports;
  late ReportFilters _filters;

  List<RatingReport> get filteredReports => _filteredReports;
  List<RatingReport> _filteredReports;

  ReportMode get mode => _filters.mode;

  void setMode(ReportMode mode) {
    _filters.mode = mode;
    _applyFilters();
    notifyListeners();
  }

  List<RatingReport> get reports => _filters.mode == ReportMode.all ? allReports : recentReports;

  void _applyFilters() {
    _filteredReports = reports.where((report) {
      return _filters.selectedTypes.contains(report.type) &&
          _filters.selectedGroups.contains(report.ratingGroupName) &&
          report.severity.index >= _filters.selectedSeverity.index;
    }).toList();
    _filteredReports.sort((a, b) {
      if(a.severity != b.severity) {
        return b.severity.index.compareTo(a.severity.index);
      }
      return a.uiTitle.compareTo(b.uiTitle);
    });
  }

  void setFilters(ReportFilters filters) {
    _filters = filters;
    _filtersChanged();
  }

  void _filtersChanged() {
    _applyFilters();
    notifyListeners();
  }

  List<RatingReportType> get selectedTypes => _filters.selectedTypes;

  void addType(RatingReportType type) {
    _filters.selectedTypes.addIfMissing(type);
    _filtersChanged();
  }

  void removeType(RatingReportType type) {
    _filters.selectedTypes.remove(type);
    _filtersChanged();
  }

  void setTypes(List<RatingReportType> types) {
    _filters.selectedTypes = types;
    _filtersChanged();
  }

  void allTypes() {
    _filters.selectedTypes = [...RatingReportType.values];
    _filtersChanged();
  }

  List<String> get selectedGroups => _filters.selectedGroups;

  void addGroup(String group) {
    _filters.selectedGroups.addIfMissing(group);
    _filtersChanged();
  }

  void removeGroup(String group) {
    _filters.selectedGroups.remove(group);
    _filtersChanged();
  }

  void setGroups(List<String> groups) {
    _filters.selectedGroups = groups;
    _filtersChanged();
  }

  void allGroups() {
    _filters.selectedGroups = [...groupNames];
    _filtersChanged();
  }

  RatingReportSeverity get selectedSeverity => _filters.selectedSeverity;

  void setSeverity(RatingReportSeverity severity) {
    _filters.selectedSeverity = severity;
    _filtersChanged();
  }

  /// Return a copy of the provided filters, without copying its listeners.
  factory ReportViewModel.copy(ReportViewModel other) {
    return ReportViewModel(
      groupNames: other.groupNames,
      allReports: other.allReports,
      recentReports: other.recentReports,
    );
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
