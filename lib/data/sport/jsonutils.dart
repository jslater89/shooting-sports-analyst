/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/registry.dart';

String sportToJson(Sport sport) {
  return sport.name;
}

Sport sportFromJson(String sportName) {
  return SportRegistry().lookup(sportName)!;
}


Map<String, bool> divisionMapToJson(Map<Division, bool> divisions) {
  return divisions.map((key, value) => MapEntry(key.name, value));
}

Map<Division, bool> divisionMapFromJson(Sport sport, Map<String, dynamic> divisions) {
  return divisions.map((key, value) => MapEntry(sport.divisions.lookupByName(key)!, value as bool));
}

Map<String, bool> classificationMapToJson(Map<Classification, bool> classifications) {
  return classifications.map((key, value) => MapEntry(key.name, value));
}

Map<Classification, bool> classificationMapFromJson(Sport sport, Map<String, dynamic> classifications) {
  return classifications.map((key, value) => MapEntry(sport.classifications.lookupByName(key)!, value as bool));
}

Map<String, bool> powerFactorMapToJson(Map<PowerFactor, bool> powerFactors) {
  return powerFactors.map((key, value) => MapEntry(key.name, value));
}

Map<PowerFactor, bool> powerFactorMapFromJson(Sport sport, Map<String, dynamic> powerFactors) {
  return powerFactors.map((key, value) => MapEntry(sport.powerFactors.lookupByName(key)!, value as bool));
}

Map<String, bool> ageCategoryMapToJson(Map<AgeCategory, bool> ageCategories) {
  return ageCategories.map((key, value) => MapEntry(key.name, value));
} 

Map<AgeCategory, bool> ageCategoryMapFromJson(Sport sport, Map<String, dynamic> ageCategories) {
  return ageCategories.map((key, value) => MapEntry(sport.ageCategories.lookupByName(key)!, value as bool));
}


