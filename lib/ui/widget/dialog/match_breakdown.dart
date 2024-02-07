/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/shooter.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';

class MatchBreakdown extends StatelessWidget {
  final List<MatchEntry> shooters;
  final Sport sport;

  const MatchBreakdown({Key? key, required this.sport, required this.shooters}) : super(key: key);

  /// To the left: a table of division/class numbers.
  @override
  Widget build(BuildContext context) {
    // totals go in null, null
    Map<_DivisionClass, int> shooterCounts = {};

    for(Division d in sport.divisions.values) {
      for(Classification c in sport.classifications.values) {
        shooterCounts[_DivisionClass(d, c)] = 0;

        // Yes, I know it repeats a bunch of times
        shooterCounts[_DivisionClass(null, c)] = 0;
      }

      shooterCounts[_DivisionClass(d, null)] = 0;
    }

    shooterCounts[_DivisionClass(null, null)] = 0;
    
    for(MatchEntry s in shooters) {
      shooterCounts[_DivisionClass(s.division, s.classification)] = shooterCounts[_DivisionClass(s.division, s.classification)]! + 1;
      shooterCounts[_DivisionClass(s.division, null)] = shooterCounts[_DivisionClass(s.division, null)]! + 1;
      shooterCounts[_DivisionClass(null, s.classification)] = shooterCounts[_DivisionClass(null, s.classification)]! + 1;
      shooterCounts[_DivisionClass(null, null)] = shooterCounts[_DivisionClass(null, null)]! + 1;
    }
    
    return AlertDialog(
      title: Text("Match Breakdown"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: _buildTable(shooterCounts)
          ),
          SizedBox(height: 12),
          _buildPowerFactor(shooters),
        ],
      )
    );
  }

  Widget _buildTable(Map<_DivisionClass, int> shooterCounts) {
    var rows = <TableRow>[];

    var divisions = <Division>[]..addAll(sport.divisions.values);

    var columns = <Widget>[
      Align(alignment: Alignment.centerRight, child: Text("")),
    ];
    for(Classification c in sport.classifications.values) {
      columns.add(
          Align(
            child: Text("${c.shortDisplayName}"),
            alignment: Alignment.centerRight,
          )
      );
    }
    columns.add(Align(alignment: Alignment.centerRight, child: Text("Total")));

    //debugPrint("$columns");
    rows.add(
      TableRow(
        children: columns,
      )
    );

    int i = 0;
    for(Division d in divisions) {
      var columns = <Widget>[];

      columns.add(Text(d.shortName));
      for(Classification c in sport.classifications.values) {
        columns.add(
          Align(
            child: Text("${shooterCounts[_DivisionClass(d, c)]}"),
            alignment: Alignment.centerRight,
          )
        );
      }

      columns.add(
        Align(
          child: Text("${shooterCounts[_DivisionClass(d, null)]}"),
          alignment: Alignment.centerRight,
        )
      );

      //debugPrint("$columns");

      rows.add(
        TableRow(
          children: columns,
          decoration: BoxDecoration(
            color: i++ % 2 == 0 ? Colors.white : Colors.grey[200],
          )
        )
      );
    }

    columns = <Widget>[];
    columns.add(Text("Total"));
    for(Classification c in sport.classifications.values) {
      columns.add(
        Align(
          child: Text("${shooterCounts[_DivisionClass(null, c)]}"),
          alignment: Alignment.centerRight,
        )
      );
    }
    columns.add(
      Align(
        child: Text("${shooterCounts[_DivisionClass(null, null)]}"),
        alignment: Alignment.centerRight,
      )
    );
    //debugPrint("$columns");
    rows.add(
      TableRow(
        children: columns,
        decoration: BoxDecoration(
          color: i++ % 2 == 0 ? Colors.white : Colors.grey[200],
        )
      ),
    );

    return Table(
      defaultColumnWidth: FixedColumnWidth(35),
      columnWidths: {
        0: FixedColumnWidth(115),
        columns.length-1: FixedColumnWidth(50),
      },
      children: rows,
    );
  }

  Widget _buildPowerFactor(List<MatchEntry> shooters) {
    Map<PowerFactor, int> pfs = {};
    for(var pf in sport.powerFactors.values) {
      pfs[pf] = shooters.where((e) => e.powerFactor == pf).length;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for(var entry in pfs.entries)
          Text("${entry.key.name}: ${entry.value}"),
      ],
    );
  }

}

class _DivisionClass {
  final Division? division;
  final Classification? classification;

  _DivisionClass(this.division, this.classification);
  
  @override
  bool operator ==(Object other) {
    if(!(other is _DivisionClass)) return false;
    // _DivisionClass o = this;
    return this.division == other.division && this.classification == other.classification;
  }

  @override
  int get hashCode => ((this.division?.toString() ?? "null") + (this.classification?.toString() ?? "null")).hashCode;

}