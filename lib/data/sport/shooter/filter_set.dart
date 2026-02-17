/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:json_annotation/json_annotation.dart';
import 'package:shooting_sports_analyst/data/sport/jsonutils.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';

part 'filter_set.g.dart';

@JsonSerializable()
class FilterSet {
  @JsonKey(toJson: sportToJson, fromJson: sportFromJson)
  Sport sport;
  FilterMode mode = FilterMode.and;
  bool reentries = true;
  bool scoreDQs = true;
  bool femaleOnly = false;

  @JsonKey(toJson: divisionMapToJson, includeToJson: true, includeFromJson: false)
  late Map<Division, bool> divisions;
  @JsonKey(toJson: classificationMapToJson, includeToJson: true, includeFromJson: false)
  late Map<Classification, bool> classifications;
  @JsonKey(toJson: powerFactorMapToJson, includeToJson: true, includeFromJson: false)
  late Map<PowerFactor, bool> powerFactors;
  @JsonKey(toJson: ageCategoryMapToJson, includeToJson: true, includeFromJson: false)
  late Map<AgeCategory, bool> ageCategories;
  @JsonKey(toJson: categoryMapToJson, includeToJson: true, includeFromJson: false)
  late Map<CompetitorCategory, bool> categories;
  List<int> squads = [];
  List<int> knownSquads;

  /// Create a filter set.
  FilterSet(this.sport, {bool empty = false, this.knownSquads = const [], List<Division>? divisions, this.mode = FilterMode.and}) {
    this.divisions = {};
    classifications = {};
    powerFactors = {};
    ageCategories = {};
    categories = {};

    for (Division d in sport.divisions.values) {
      this.divisions[d] = !empty;
    }

    for (Classification c in sport.classifications.values) {
      classifications[c] = !empty;
    }

    for (PowerFactor f in sport.powerFactors.values) {
      powerFactors[f] = !empty;
    }

    for (AgeCategory c in sport.ageCategories.values) {
      ageCategories[c] = false;
    }

    for (CompetitorCategory c in sport.categories.values) {
      categories[c] = false;
    }

    for(var d in divisions ?? []) {
      this.divisions[d] = true;
    }

    if(!empty) {
      squads = knownSquads;
    }
  }

  Iterable<Division> get activeDivisions => divisions.keys.where((div) => divisions[div] ?? false);
  Iterable<Classification> get activeClassifications => classifications.keys.where((c) => classifications[c] ?? false);
  Iterable<PowerFactor> get activePowerFactors => powerFactors.keys.where((f) => powerFactors[f] ?? false);
  Iterable<AgeCategory> get activeAgeCategories => ageCategories.keys.where((c) => ageCategories[c] ?? false);
  Iterable<CompetitorCategory> get activeCategories => categories.keys.where((c) => categories[c] ?? false);

  static Map<Division, bool> divisionListToMap(Sport sport, List<Division> divisions) {
    Map<Division, bool> map = {};
    for(var d in sport.divisions.values) {
      map[d] = divisions.contains(d);
    }

    return map;
  }

  FilterSet copy() {
    return FilterSet.fromJson(toJson());
  }

  factory FilterSet.fromJson(Map<String, dynamic> json) {
    var set = _$FilterSetFromJson(json);
    var divisionMap = json['divisions'] as Map<String, dynamic>;
    set.divisions = divisionMapFromJson(set.sport, divisionMap);

    var classificationMap = json['classifications'] as Map<String, dynamic>;
    set.classifications = classificationMapFromJson(set.sport, classificationMap);

    var powerFactorMap = json['powerFactors'] as Map<String, dynamic>;
    set.powerFactors = powerFactorMapFromJson(set.sport, powerFactorMap);

    var ageCategoryMap = json['ageCategories'] as Map<String, dynamic>;
    set.ageCategories = ageCategoryMapFromJson(set.sport, ageCategoryMap);

    var categoryMap = json['categories'] as Map<String, dynamic>;
    set.categories = categoryMapFromJson(set.sport, categoryMap);

    return set;
  }

  factory FilterSet.forDivision(Sport sport, Division division) {
    return FilterSet(sport, divisions: [division], empty: true, mode: FilterMode.or);
  }

  Map<String, dynamic> toJson() {
    return _$FilterSetToJson(this);
  }

  bool get isEmpty =>
    squads.isEmpty
    && !femaleOnly
    && activeDivisions.isEmpty
    && activeClassifications.isEmpty
    && activePowerFactors.isEmpty
    && activeAgeCategories.isEmpty
    && activeCategories.isEmpty;
}

enum FilterMode {
  or, and,
}
