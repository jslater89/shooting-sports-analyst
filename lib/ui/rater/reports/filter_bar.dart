import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/rating_report.dart';
import 'package:shooting_sports_analyst/ui/rater/reports/report_view.dart';

class ReportFilterBar extends StatelessWidget {
  const ReportFilterBar({super.key});

  @override
  Widget build(BuildContext context) {
    var filterModel = Provider.of<ReportViewModel>(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      mainAxisSize: MainAxisSize.max,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: "Severity",
                isDense: true,
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<RatingReportSeverity>(
                  value: filterModel.selectedSeverity,
                  onChanged: (value) => filterModel.setSeverity(value!),
                  items: RatingReportSeverity.values.map((e) => DropdownMenuItem(
                    value: e,
                    child: Row(
                      children: [
                        Icon(e.uiIcon, color: e.uiColor),
                        SizedBox(width: 24),
                        Text(e.uiLabel),
                      ],
                    ))).toList(),
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: "Type",
                isDense: true,
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<RatingReportType?>(
                  value: filterModel.selectedTypes.length > 1 ? null : filterModel.selectedTypes.first,
                  hint: Text("All"),
                  onChanged: (value) {
                    if(value == null) {
                      filterModel.allTypes();
                    } else {
                      filterModel.setTypes([value]);
                    }
                  },
                  items: _typeValues.map((e) => DropdownMenuItem(value: e, child: Text(e?.dropdownName ?? "All"))).toList(),
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: "Group",
                isDense: true,
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: filterModel.selectedGroups.length > 1 ? null : filterModel.selectedGroups.first,
                  hint: Text("All"),
                  onChanged: (value) {
                    if(value == null) {
                      filterModel.allGroups();
                    } else {
                      filterModel.setGroups([value]);
                    }
                  },
                  items: [null, ...filterModel.groupNames].map((e) => DropdownMenuItem(value: e, child: Text(e ?? "All"))).toList(),
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: "Mode",
                isDense: true,
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<ReportMode>(
                  value: filterModel.mode,
                  onChanged: (value) => filterModel.setMode(value!),
                  items: ReportMode.values.map((e) => DropdownMenuItem(value: e, child: Text(e.uiLabel))).toList(),
                ),
              ),
            ),
          ),
        ),
        
      ],
    );
  }
}

List<RatingReportType?> _typeValues = [null, ...RatingReportType.values];