/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/config/config.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/db_statistics.dart';
import 'package:shooting_sports_analyst/util.dart';

class DbStatisticsDialog extends StatefulWidget {
  const DbStatisticsDialog({super.key, required this.stats});

  final DatabaseStatistics stats;

  @override
  State<DbStatisticsDialog> createState() => _DbStatisticsDialogState();
}

class _DbStatisticsDialogState extends State<DbStatisticsDialog> {
  bool _loadedDetailedStats = false;

  @override
  Widget build(BuildContext context) {
    var uiScaleFactor = ChangeNotifierConfigLoader().uiConfig.uiScaleFactor;
    return AlertDialog(
      title: Text("Database statistics"),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Basic statistics", style: Theme.of(context).textTheme.titleMedium!.copyWith(decoration: TextDecoration.underline)),
            SizedBox(height: 10),
            Table(
              columnWidths: const {
                0: FixedColumnWidth(200),
                1: FixedColumnWidth(100),
                2: FixedColumnWidth(100),
                3: FixedColumnWidth(100),
              },
              children: [
                TableRow(
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide())
                  ),
                  children: [
                    Text("Entity", style: Theme.of(context).textTheme.bodyLarge, textAlign: TextAlign.left),
                    Text("Count", style: Theme.of(context).textTheme.bodyLarge, textAlign: TextAlign.right),
                    Text("Size", style: Theme.of(context).textTheme.bodyLarge, textAlign: TextAlign.right),
                    Text("Average size", style: Theme.of(context).textTheme.bodyLarge, textAlign: TextAlign.right),
                  ],
                ),
                TableRow(
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide())
                  ),
                  children: [
                    Text("Matches", style: Theme.of(context).textTheme.bodyLarge),
                    Text("${widget.stats.matchCount}", style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.right),
                    Text("${_formatMiB(widget.stats.matchSize)}", style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.right),
                    Text("${_formatBytes(widget.stats.averageMatchSize)}", style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.right),
                  ],
                ),
                TableRow(
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide())
                  ),
                  children: [
                    Text("Rating projects", style: Theme.of(context).textTheme.bodyLarge),
                    Text("${widget.stats.ratingProjectCount}", style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.right),
                    Text("${_formatMiB(widget.stats.ratingProjectSize)}", style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.right),
                    Text("${_formatBytes(widget.stats.averageProjectSize)}", style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.right),
                  ],
                ),
                TableRow(
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide())
                  ),
                  children: [
                    Text("Ratings", style: Theme.of(context).textTheme.bodyLarge),
                    Text("${widget.stats.ratingCount}", style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.right),
                    Text("${_formatMiB(widget.stats.ratingSize)}", style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.right),
                    Text("${_formatBytes(widget.stats.averageRatingSize)}", style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.right),
                  ],
                ),
                TableRow(
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide())
                  ),
                  children: [
                    Text("Events", style: Theme.of(context).textTheme.bodyLarge),
                    Text("${widget.stats.eventCount}", style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.right),
                    Text("${_formatMiB(widget.stats.eventSize)}", style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.right),
                    Text("${_formatBytes(widget.stats.averageEventSize)}", style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.right),
                  ],
                ),
              ],
            ),
            SizedBox(height: 10),
            if(!_loadedDetailedStats)
              TextButton(
                onPressed: () async {
                  await AnalystDatabase().loadPerProjectDatabaseStatistics(widget.stats);
                  setState(() {
                    _loadedDetailedStats = true;
                  });
                },
                child: Text("LOAD PROJECT STATISTICS"),
              ),
            if(_loadedDetailedStats)
              ..._detailedStats(),
            SizedBox(height: 10),
            Text("Total size: ${_formatMiB(widget.stats.totalSize)} (${(widget.stats.totalSize / widget.stats.maxSize).asPercentage(decimals: 1)}% full)"),
          ],
        ),
      )
    );
  }

  String _formatMiB(num bytes) {
    return "${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB";
  }

  String _formatBytes(num bytes) {
    if(bytes > 1024 * 1024) {
      return _formatMiB(bytes);
    }
    if(bytes > 1024) {
      return "${(bytes / 1024).toStringAsFixed(1)} KiB";
    }
    return "${bytes.round()} bytes";
  }

  List<Widget> _detailedStats() {
    List<TableRow> stats = [];
    stats.add(TableRow(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide())
      ),
      children: [
        Text("Project", style: Theme.of(context).textTheme.bodyLarge),
        Text("Ratings", style: Theme.of(context).textTheme.bodyLarge, textAlign: TextAlign.right),
        Text("Events", style: Theme.of(context).textTheme.bodyLarge, textAlign: TextAlign.right),
        Text("Size", style: Theme.of(context).textTheme.bodyLarge, textAlign: TextAlign.right),
      ],
    ));
    for(var project in widget.stats.ratingProjectRatingCounts.keys) {
      if(project.name == "autosave") {
        continue;
      }
      stats.add(TableRow(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide())
        ),
        children: [
          Tooltip(
            message: project.name,
            waitDuration: Duration(milliseconds: 1000),
            child: Text(project.name, style: Theme.of(context).textTheme.bodyLarge, softWrap: false, overflow: TextOverflow.ellipsis)
          ),
          Text("\t${widget.stats.ratingProjectRatingCounts[project]}", style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.right),
          Text("\t${widget.stats.ratingProjectEventCounts[project]}", style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.right),
          Text("\t${_formatBytes(widget.stats.estimatedProjectSizes[project]!)}", style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.right),
        ],
      ));
    }
    return [
      Text("Project statistics", style: Theme.of(context).textTheme.titleMedium!.copyWith(decoration: TextDecoration.underline)),
      SizedBox(height: 10),
      Table(
        columnWidths: const {
          0: FixedColumnWidth(200),
          1: FixedColumnWidth(100),
          2: FixedColumnWidth(100),
          3: FixedColumnWidth(100),
        },
        children: stats,
      ),
    ];
  }
}