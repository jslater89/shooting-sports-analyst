/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/ui/booth/controller.dart';
import 'package:shooting_sports_analyst/ui/booth/global_card_settings_dialog.dart';
import 'package:shooting_sports_analyst/ui/booth/model.dart';
import 'package:shooting_sports_analyst/ui/booth/scorecard.dart';
import 'package:shooting_sports_analyst/ui/booth/scorecard_model.dart';

SSALogger _log = SSALogger("BoothScorecardGrid");

class ScorecardGridSizeModel {
  ScorecardGridSizeModel({
    required this.screenSize,
  }) {
    cardHeight = minScorecardHeight;
    cardWidth = minScorecardWidth;
  }

  double minScorecardWidth = 900.0;
  double minScorecardHeight = 400.0;

  int rowCount = 1;
  int columnCount = 1;

  late double cardHeight;
  late double cardWidth;

  Size screenSize;

  void update({int? rowCount, int? columnCount, Size? size}) {
    if (rowCount != null) {
      this.rowCount = max(1, rowCount);
    }

    if (columnCount != null) {
      this.columnCount = max(1, columnCount);
    }

    if (size != null) {
      screenSize = size;
    }

    var adjustedHeight = screenSize.height;
    var adjustedWidth = screenSize.width;

    double provisionalCardHeight = adjustedHeight / this.rowCount;
    double provisionalCardWidth = adjustedWidth / this.columnCount;

    this.cardHeight = max(provisionalCardHeight, minScorecardHeight);
    this.cardWidth = max(provisionalCardWidth, minScorecardWidth);

    _log.v("Scorecard grid size ${this.rowCount}x${this.columnCount} -> ${this.cardHeight}x${this.cardWidth}");

    // notifyListeners();
  }

  void applyFrom(GlobalScorecardSettingsModel settings) {
    this.minScorecardHeight = settings.minScorecardHeight;
    this.minScorecardWidth = settings.minScorecardWidth;
    this.update();
  }
}

class BoothScorecardGrid extends StatelessWidget {
  const BoothScorecardGrid({super.key});

  @override
  Widget build(BuildContext context) {
    var size = MediaQuery.of(context).size;

    return Column(
      children: [
        Expanded(
          child: ScorecardInnerGrid(),
        ),
        SizedBox(
          width: size.width,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.max,
            children: [

            ],
          ),
        )
      ],
    );
  }
}

class ScorecardInnerGrid extends StatefulWidget {
  ScorecardInnerGrid({
    super.key,
  });

  @override
  State<ScorecardInnerGrid> createState() => _ScorecardInnerGridState();
}

class _ScorecardInnerGridState extends State<ScorecardInnerGrid> {
  late ScorecardGridSizeModel _gridSizeModel;
  final ScrollController _verticalScrollController = ScrollController();
  final ScrollController _horizontalScrollController = ScrollController();

  @override
  void initState() {
    super.initState();

    _gridSizeModel = ScorecardGridSizeModel(screenSize: Size(1280, 720));
  }

  @override
  Widget build(BuildContext context) {
    var model = context.watch<BroadcastBoothModel>();
    var controller = context.watch<BroadcastBoothController>();

    if(model.scorecardCount == 0) {
      return Center(
        child: TextButton(
          child: Text("ADD DEFAULT SCORECARDS"),
          onPressed: () {
            controller.addDefaultScorecards();
          },
        )
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if(model.maximizedScorecardId != null) {
          var scorecard = model.maximizedScorecard;
          _gridSizeModel.update(rowCount: 1, columnCount: 1, size: constraints.biggest);
          return Provider.value(
            value: _gridSizeModel,
            child: BoothScorecard(key: ValueKey(scorecard.hashCode), scorecard: scorecard!),
          );
        }

        int rowCount = model.scorecards.length;
        int columnCount = model.scorecards.map((row) => row.length).maxOrNull ?? 0;

        _gridSizeModel.applyFrom(model.globalScorecardSettings);
        _gridSizeModel.update(rowCount: rowCount, columnCount: columnCount, size: constraints.biggest);
        return Provider.value(
          value: _gridSizeModel,
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            controller: _verticalScrollController,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              controller: _horizontalScrollController,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...model.scorecards.map((row) => BoothScorecardRow(scorecardRow: row)),
                ],
              ),
            ),
          ),
        );
      }
    );
  }
}

class BoothScorecardRow extends StatelessWidget {
  const BoothScorecardRow({super.key, required this.scorecardRow});

  final List<ScorecardModel> scorecardRow;

  @override
  Widget build(BuildContext context) {
    var controller = context.watch<BroadcastBoothController>();
    var sizeModel = context.read<ScorecardGridSizeModel>();
    var children = <Widget>[];
    children.addAll(scorecardRow.map((scorecard) => BoothScorecard(key: ValueKey(scorecard.hashCode), scorecard: scorecard)).toList());
    if(scorecardRow.length < sizeModel.columnCount) {
      children.add(Container(
        width: sizeModel.cardWidth,
        height: sizeModel.cardHeight,
        child: Center(
          child: IconButton.filled(
            icon: Icon(Icons.add),
            onPressed: () {
              controller.addScorecardColumn(scorecardRow);
            },
          ),
        ),
      ));
    }

    return Row(
      mainAxisSize: MainAxisSize.max,
      mainAxisAlignment: MainAxisAlignment.start,
      children: children,
    );
  }
}
