// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.


import 'package:json_annotation/json_annotation.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';

part 'json_shooter_rating.g.dart';

@JsonSerializable()
class JsonShooterRating {
  final String memberNumber;
  final String name;
  final String division;
  final String lastClassification;
  final double rating;

  JsonShooterRating({
    required this.memberNumber,
    required this.name,
    required this.division,
    required this.lastClassification,
    required this.rating,
  });

  JsonShooterRating.fromShooterRating(ShooterRating rating) :
    memberNumber = rating.memberNumber,
    name = rating.getName(suffixes: false),
    division = rating.division?.name ?? "(unknown)",
    lastClassification = rating.lastClassification.name,
    rating = rating.rating;

  factory JsonShooterRating.fromJson(Map<String, dynamic> json) => _$JsonShooterRatingFromJson(json);
  Map<String, dynamic> toJson() => _$JsonShooterRatingToJson(this);
}