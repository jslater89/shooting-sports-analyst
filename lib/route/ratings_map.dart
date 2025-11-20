import 'dart:math' show min, max;

import 'package:collection/collection.dart';
import 'package:color_models/color_models.dart';
import 'package:data/data.dart' show WeibullDistribution;
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:shooting_sports_analyst/config/config.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/ranking/interface/rating_data_source.dart';
import 'package:shooting_sports_analyst/data/ranking/scaling/rating_scaler.dart';
import 'package:shooting_sports_analyst/data/ranking/scaling/standardized_maximum_scaler.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/ui/empty_scaffold.dart';
import 'package:shooting_sports_analyst/ui/widget/color_legend.dart';
import 'package:shooting_sports_analyst/ui/widget/custom_tooltip.dart';
import 'package:shooting_sports_analyst/ui/widget/us_data_map.dart';
import 'package:shooting_sports_analyst/ui_util.dart';
import 'package:shooting_sports_analyst/util.dart';

var _log = SSALogger("RatingsMap");

class RatingsMap extends StatefulWidget {
  const RatingsMap({super.key, required this.dataSource});

  final RatingDataSource dataSource;

  @override
  State<RatingsMap> createState() => _RatingsMapState();
}

class _RatingsMapState extends State<RatingsMap> {
  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Map<String, double> _ratingsByState = {};
  Map<String, int> _totalCompetitorsByState = {};
  Map<String, int> _gmCountByState = {};
  Map<String, double> _classificationStrengthByState = {};
  int _totalLocatedRatings = 0;
  ColorMode _colorMode = ColorMode.ratings;

  Future<void> _loadData() async {
    var dataSource = widget.dataSource;

    var sportRes = await dataSource.getSport();
    if(sportRes.isErr()) {
      _log.w("Error getting sport: ${sportRes.unwrapErr()}");
      return;
    }
    var sport = sportRes.unwrap();

    var groupsRes = await dataSource.getGroups();
    if(groupsRes.isErr()) {
      _log.w("Error getting groups: ${groupsRes.unwrapErr()}");
      return;
    }
    var groups = groupsRes.unwrap();
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
      for(var rating in ratings) {
        ratingScalerMin = min(ratingScalerMin, rating.rating);
        ratingScalerMax = max(ratingScalerMax, rating.rating);
      }
      var scaler = StandardizedMaximumScaler(
        scaleMax: 2000,
        info: RatingScalerInfo(
          minRating: ratingScalerMin,
          maxRating: ratingScalerMax,
          top2PercentAverage: 0,
          ratingDistribution: WeibullDistribution(1, 1),
          ratingMean: 0,
          ratingStdDev: 1,
        ),
      );
      for(var rating in ratings) {
        // if(rating.lastSeen.isBefore(DateTime(2024, 1, 1))) {
        //   continue;
        // }
        totalRatings++;
        if(rating.regionSubdivision != null) {
          ratingsByLocation.addToList(rating.regionSubdivision!, scaler.scaleRating(rating.rating));
          knownLocations.add(rating.regionSubdivision!);
          classificationStrengthsByLocation.addToList(rating.regionSubdivision!, sport.ratingStrengthProvider?.strengthForClass(rating.lastClassification) ?? 1.0);

          if(rating.lastClassificationName != null && rating.lastClassificationName! == "Grandmaster") {
            _gmCountByState.increment(rating.regionSubdivision!);
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
      _ratingsByState[location] = ratings.weightedAverage(weights);
      _totalCompetitorsByState[location] = totalRatingCountAtLocation;
      _classificationStrengthByState[location] = classificationStrengths.average;
      _totalLocatedRatings += totalRatingCountAtLocation;
    }

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
    Map<String, double> data = {};
    double maxValue = 1;
    double minValue = 0;
    if(_colorMode == ColorMode.ratings) {
      data = _ratingsByState;
    }
    else if(_colorMode == ColorMode.competitorCount) {
      data = _totalCompetitorsByState.map((key, value) => MapEntry(key, value.toDouble()));
    }
    else if(_colorMode == ColorMode.classificationStrength) {
      data = _classificationStrengthByState.map((key, value) => MapEntry(key, value.toDouble()));
    }
    else if(_colorMode == ColorMode.gmCount) {
      data = _gmCountByState.map((key, value) => MapEntry(key, value.toDouble()));
    }
    else if(_colorMode == ColorMode.classificationStrength) {
      data = _classificationStrengthByState.map((key, value) => MapEntry(key, value.toDouble()));
    }
    if(data.isNotEmpty) {
      maxValue = data.values.max;
      minValue = data.values.min;
    }
    if(_svgWidget == null) {
      _svgWidget = USDataMap(
        data: data,
        rgbColors: _referenceColors,
        tooltipTextBuilder: (state) {
          if(_colorMode == ColorMode.ratings) {
            return "${state} average rating: ${_ratingsByState[state]?.toStringAsFixed(1)}";
          }
          else if(_colorMode == ColorMode.competitorCount) {
            return "${state}: ${_totalCompetitorsByState[state]?.toString()} competitors";
          }
          else if(_colorMode == ColorMode.classificationStrength) {
            return "${state}: ${_classificationStrengthByState[state]?.toStringAsFixed(1)} classification strength";
          }
          else if(_colorMode == ColorMode.gmCount) {
            return "${state}: ${(_gmCountByState[state] ?? 0).toString()} GMs";
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
            if(data.isNotEmpty) ColorLegend(
              legendEntries: 10,
              minValue: minValue,
              maxValue: maxValue,
              referenceColors: _referenceColors,
              labelDecimals: _colorMode == ColorMode.ratings ? 1 : 0,
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
  gmCount;

  String get uiLabel => switch(this) {
    ratings => "Ratings",
    competitorCount => "Competitor count",
    classificationStrength => "Classification strength",
    gmCount => "GM count",
  };
}
