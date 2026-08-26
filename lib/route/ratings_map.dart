/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math' show min, max;

import 'package:collection/collection.dart';
import 'package:color_models/color_models.dart';
import 'package:data/data.dart' show WeibullDistribution;
import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/config/config.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/ranking/interface/rating_data_source.dart';
import 'package:shooting_sports_analyst/data/ranking/scaling/rating_scaler.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/ui/empty_scaffold.dart';
import 'package:shooting_sports_analyst/ui/widget/color_legend.dart';
import 'package:shooting_sports_analyst/ui/widget/us_data_map.dart';
import 'package:shooting_sports_analyst/ui_util.dart';
import 'package:shooting_sports_analyst/util.dart';

var _log = SSALogger("RatingsMap");

class RatingsMap extends StatefulWidget {
  const RatingsMap({super.key, required this.dataSource, this.launchGroup});

  final RatingDataSource dataSource;
  final RatingGroup? launchGroup;

  @override
  State<RatingsMap> createState() => _RatingsMapState();
}

class _RatingsMapState extends State<RatingsMap> {
  @override
  void initState() {
    super.initState();
    _loadData(allGroups: true, useStandardScaler: true);
  }

  ColorMode _colorMode = ColorMode.ratings;
  bool allGroups = true;
  _RatingsMapData get data => allGroups ? _allGroupsData : _launchGroupData;
  _RatingsMapData _allGroupsData = _RatingsMapData();
  bool loadedAllGroups = false;

  _RatingsMapData _launchGroupData = _RatingsMapData();
  bool loadedLaunchGroup = false;

  Future<void> _loadData({bool allGroups = true, bool useStandardScaler = true}) async {
    if(allGroups && loadedAllGroups) {
      _log.i("Setting data to all groups data");
      _rebuildMap();
      return;
    }
    if(!allGroups && loadedLaunchGroup) {
      _log.i("Setting data to launch group data");
      _rebuildMap();
      return;
    }

    final wipData = _RatingsMapData();

    var dataSource = widget.dataSource;

    var sportRes = await dataSource.getSport();
    if(sportRes.isErr()) {
      _log.w("Error getting sport: ${sportRes.unwrapErr()}");
      return;
    }
    var sport = sportRes.unwrap();

    List<RatingGroup> groups = [];
    if(allGroups) {
      var groupsRes = await dataSource.getGroups();
      if(groupsRes.isErr()) {
        _log.w("Error getting groups: ${groupsRes.unwrapErr()}");
        return;
      }
      groups = groupsRes.unwrap();
    }
    else {
      groups = [widget.launchGroup!];
    }

    /// For each group, a map of location to a list of ratings at that location.
    Map<RatingGroup, Map<String, List<double>>> ratingsByLocationByGroup = {};
    /// For each group, the total number of ratings in the group across all locations.
    Map<RatingGroup, int> totalGroupSizes = {};
    Set<String> knownLocations = {};
    Map<RatingGroup, Map<String, List<double>>> classificationStrengthByLocationByGroup = {};
    for(var group in groups) {
      double ratingScalerMin = double.infinity;
      double ratingScalerMax = double.negativeInfinity;

      var ratingsByLocation = <String, List<double>>{};
      var classificationStrengthsByLocation = <String, List<double>>{};

      var ratingsRes = await dataSource.getRatings(group);
      if(ratingsRes.isErr()) {
        _log.w("Error getting ratings for group ${group.name}: ${ratingsRes.unwrapErr()}");
        continue;
      }
      var ratings = ratingsRes.unwrap();
      int totalRatings = 0;

      RatingScaler? scaler;
      if(useStandardScaler) {
        for(var rating in ratings) {
          ratingScalerMin = min(ratingScalerMin, rating.rating);
          ratingScalerMax = max(ratingScalerMax, rating.rating);
        }
        var scalerRes = await dataSource.getStandardScaler();
        if(scalerRes.isErr()) {
          _log.w("Error getting standard scaler: ${scalerRes.unwrapErr()}");
          continue;
        }
        scaler = scalerRes.unwrap();

        scaler.info = RatingScalerInfo(
          minRating: ratingScalerMin,
          maxRating: ratingScalerMax,
          top2PercentAverage: 0,
          ratingDistribution: WeibullDistribution(1, 1),
          ratingMean: 0,
          ratingStdDev: 1,
        );
      }

      for(var rating in ratings) {
        if(rating.lastSeen.isBefore(DateTime(2024, 1, 1))) {
          continue;
        }
        totalRatings++;
        if(rating.regionSubdivision != null) {
          final scaledResult = scaler?.scaleRating(rating.rating) ?? rating.rating;
          final numericRatingResult = await dataSource.scaleRating(scaledResult);
          if(numericRatingResult.isErr()) {
            _log.w("Error scaling rating: ${numericRatingResult.unwrapErr()}");
            continue;
          }
          final numericRating = numericRatingResult.unwrap();
          ratingsByLocation.addToList(rating.regionSubdivision!, numericRating);
          knownLocations.add(rating.regionSubdivision!);
          classificationStrengthsByLocation.addToList(rating.regionSubdivision!, sport.ratingStrengthProvider?.strengthForClass(rating.lastClassification) ?? 1.0);

          if(rating.lastClassificationName != null && rating.lastClassificationName! == "Grandmaster") {
            wipData.gmCountByState.increment(rating.regionSubdivision!);
          }
        }

        ratingsByLocationByGroup[group] = ratingsByLocation;
        classificationStrengthByLocationByGroup[group] = classificationStrengthsByLocation;
      }
      totalGroupSizes.incrementBy(group, totalRatings);
    }
    var totalRatingCount = totalGroupSizes.values.sum;

    // Map values:
    // - per state, weighted average rating by division size
    // - per state, total count of ratings
    for(var location in knownLocations) {
      int totalRatingCountAtLocation = ratingsByLocationByGroup.values.map((e) => e[location]?.length ?? 0).sum;
      List<double> ratings = [];
      List<double> weights = [];
      List<double> classificationStrengths = [];

      for(var group in groups) {
        var locationRatings = ratingsByLocationByGroup[group]![location];
        var locationClassificationStrengths = classificationStrengthByLocationByGroup[group]![location];

        if(locationRatings != null) {
          int totalGroupSize = totalGroupSizes[group]!;
          double averageRatingAtLocation = locationRatings.average;
          weights.add(totalGroupSize / totalRatingCount);
          ratings.add(averageRatingAtLocation);
        }
        if(locationClassificationStrengths != null) {
          double averageClassificationStrengthAtLocation = locationClassificationStrengths.average;
          classificationStrengths.add(averageClassificationStrengthAtLocation);
        }
      }
      wipData.ratingsByState[location] = ratings.weightedAverage(weights);
      wipData.totalCompetitorsByState[location] = totalRatingCountAtLocation;
      wipData.classificationStrengthByState[location] = classificationStrengths.average;
      wipData.totalLocatedRatings += totalRatingCountAtLocation;
    }

    if(allGroups) {
      _allGroupsData = wipData;
      loadedAllGroups = true;
    }
    else {
      _launchGroupData = wipData;
      loadedLaunchGroup = true;
    }

    _log.i("Total located ratings: ${wipData.totalLocatedRatings}");
    _log.i("Total ratings: $totalRatingCount");
    _log.i("Total located ratings: ${(wipData.totalLocatedRatings / totalRatingCount).asPercentage(decimals: 1, includePercent: true)}");
    _rebuildMap();
  }

  USDataMap? _svgWidget;
  List<RgbColor> get _referenceColors => _colorScheme.referenceColors;
  LerpColorScheme _colorScheme = LerpColorScheme.thermal;


  void _rebuildMap() {
    setState(() {
      _svgWidget = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final uiScaleFactor = ChangeNotifierConfigLoader().uiConfig.uiScaleFactor;
    Map<String, double> colorData = {};
    double maxValue = 1;
    double minValue = 0;
    if(_colorMode == ColorMode.ratings) {
      colorData = data.ratingsByState;
    }
    else if(_colorMode == ColorMode.competitorCount) {
      colorData = data.totalCompetitorsByState.map((key, value) => MapEntry(key, value.toDouble()));
    }
    else if(_colorMode == ColorMode.classificationStrength) {
      colorData = data.classificationStrengthByState.map((key, value) => MapEntry(key, value.toDouble()));
    }
    else if(_colorMode == ColorMode.gmCount) {
      colorData = data.gmCountByState.map((key, value) => MapEntry(key, value.toDouble()));
    }
    else if(_colorMode == ColorMode.classificationStrength) {
      colorData = data.classificationStrengthByState.map((key, value) => MapEntry(key, value.toDouble()));
    }
    else if(_colorMode == ColorMode.gmRatio) {
      colorData = data.gmCountByState.map((key, value) => MapEntry(key, value.toDouble() / data.totalCompetitorsByState[key]!.toDouble() * 100));
    }
    if(colorData.isNotEmpty) {
      maxValue = colorData.values.max;
      minValue = colorData.values.min;
    }
    if(_svgWidget == null) {
      _svgWidget = USDataMap(
        data: colorData,
        rgbColors: _referenceColors,
        tooltipTextBuilder: (state) {
          if(_colorMode == ColorMode.ratings) {
            return "${state} average rating: ${data.ratingsByState[state]?.toStringAsFixed(1) ?? "n/a"}";
          }
          else if(_colorMode == ColorMode.competitorCount) {
            return "${state}: ${data.totalCompetitorsByState[state]?.toString() ?? "0"} competitors";
          }
          else if(_colorMode == ColorMode.classificationStrength) {
            return "${state}: ${data.classificationStrengthByState[state]?.toStringAsFixed(1) ?? "n/a"} classification strength";
          }
          else if(_colorMode == ColorMode.gmCount) {
            return "${state}: ${(data.gmCountByState[state] ?? 0).toString()} GMs";
          }
          else if(_colorMode == ColorMode.gmRatio) {
            return "${state}: ${((data.gmCountByState[state] ?? 0).toDouble() / (data.totalCompetitorsByState[state] ?? 0)).asPercentage(decimals: 1, includePercent: true)} GMs";
          }
          return "$state";
        },
      );
    }
    return EmptyScaffold(
      title: "Ratings Map",
      actions: [
        IconButton(
          icon: Icon(Icons.refresh),
          onPressed: () {
            _rebuildMap();
          },
        ),
        Tooltip(
          message: "Toggle between weighted average over all groups and raw data from the launched group",
          child: IconButton(
            icon: Icon(Icons.swap_horiz),
            onPressed: () {
              allGroups = !allGroups;
              _loadData(allGroups: allGroups, useStandardScaler: true);
              // loadData rebuilds the map after loading.
            },
          ),
        )
      ],
      child: Padding(
        padding: EdgeInsets.all(8 * uiScaleFactor),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          spacing: 8 * uiScaleFactor,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 8 * uiScaleFactor,
              children: [
                DropdownMenu<ColorMode>(
                  initialSelection: _colorMode,
                  label: Text("Data"),
                  dropdownMenuEntries: ColorMode.values.map((e) => DropdownMenuEntry(value: e, label: e.uiLabel)).toList(),
                  onSelected: (value) {
                    if(value != null) {
                      _colorMode = value;
                      _rebuildMap();
                    }
                  },
                ),
                DropdownMenu<LerpColorScheme>(
                  initialSelection: _colorScheme,
                  label: Text("Color scheme"),
                  dropdownMenuEntries: LerpColorScheme.values.map((e) => DropdownMenuEntry(value: e, label: e.uiLabel)).toList(),
                  onSelected: (value) {
                    if(value != null) {
                      _colorScheme = value;
                      _rebuildMap();
                    }
                  },
                )
              ],
            ),
            if(colorData.isNotEmpty) ColorLegend(
              legendEntries: 10,
              minValue: minValue,
              maxValue: maxValue,
              referenceColors: _referenceColors,
              labelDecimals: _colorMode == ColorMode.ratings || _colorMode == ColorMode.gmRatio ? 1 : 0,
            ),
            Expanded(
              child: _svgWidget!,
            ),
          ],
        ),
      ),
    );
  }
}

enum ColorMode {
  ratings,
  competitorCount,
  classificationStrength,
  gmCount,
  gmRatio;

  String get uiLabel => switch(this) {
    ratings => "Ratings",
    competitorCount => "Competitor count",
    classificationStrength => "Classification strength",
    gmCount => "GM count",
    gmRatio => "GM ratio",
  };
}

class _RatingsMapData {
  Map<String, double> ratingsByState = {};
  Map<String, int> totalCompetitorsByState = {};
  Map<String, int> gmCountByState = {};
  Map<String, double> classificationStrengthByState = {};
  int totalLocatedRatings = 0;
}