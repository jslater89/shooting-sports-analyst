import 'package:flutter/material.dart';
import 'package:uspsa_result_viewer/data/model.dart';

class MatchBreakdown extends StatelessWidget {
  final List<Shooter> shooters;

  const MatchBreakdown({Key? key, required this.shooters}) : super(key: key);

  /// To the left: a table of division/class numbers.
  @override
  Widget build(BuildContext context) {
    // totals go in null, null
    Map<_DivisionClass, int> shooterCounts = {};

    for(Division d in Division.values) {
      for(USPSAClassification c in USPSAClassification.values) {
        shooterCounts[_DivisionClass(d, c)] = 0;

        // Yes, I know it repeats a bunch of times
        shooterCounts[_DivisionClass(null, c)] = 0;
      }

      shooterCounts[_DivisionClass(d, null)] = 0;
    }

    shooterCounts[_DivisionClass(null, null)] = 0;
    
    for(Shooter s in shooters) {
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

    var divisions = <Division>[]..addAll(Division.values)..remove(Division.unknown);

    var columns = <Widget>[
      Align(alignment: Alignment.centerRight, child: Text("")),
      Align(alignment: Alignment.centerRight, child: Text("GM")),
      Align(alignment: Alignment.centerRight, child: Text("M")),
      Align(alignment: Alignment.centerRight, child: Text("A")),
      Align(alignment: Alignment.centerRight, child: Text("B")),
      Align(alignment: Alignment.centerRight, child: Text("C")),
      Align(alignment: Alignment.centerRight, child: Text("D")),
      Align(alignment: Alignment.centerRight, child: Text("U")),
      Align(alignment: Alignment.centerRight, child: Text("?")),
      Align(alignment: Alignment.centerRight, child: Text("Total")),
    ];
    //debugPrint("$columns");
    rows.add(
      TableRow(
        children: columns,
      )
    );

    int i = 0;
    for(Division d in divisions) {
      var columns = <Widget>[];

      columns.add(Text(d.displayString()));
      for(USPSAClassification c in USPSAClassification.values) {
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
    for(USPSAClassification c in USPSAClassification.values) {
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
      )
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

  Widget _buildPowerFactor(List<Shooter> shooters) {
    int major = shooters.where((element) => element.powerFactor == PowerFactor.major).length;
    int minor = shooters.where((element) => element.powerFactor == PowerFactor.minor).length;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text("Major: $major"),
        Text("Minor: $minor"),
      ],
    );
  }

}

class _DivisionClass {
  final Division? division;
  final USPSAClassification? classification;

  _DivisionClass(this.division, this.classification);
  
  @override
  bool operator ==(Object other) {
    if(!(other is _DivisionClass)) return false;
    _DivisionClass o = this;
    return this.division == o.division && this.classification == o.classification;
  }

  @override
  int get hashCode => ((this.division?.toString() ?? "null") + (this.classification?.toString() ?? "null")).hashCode;

}