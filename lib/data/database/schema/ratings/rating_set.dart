/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:isar/isar.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';

part 'rating_set.g.dart';

/// A rating set is a collection of member numbers of interest, which can be used
/// to filter the ratings display pages.
@collection
class RatingSet {
  Id id = Isar.autoIncrement;

  /// The name of the rating set. If unset, whenever this set is applied, a short list
  /// of matching names will be used instead.
  String? name;

  /// The display name of the rating set. Use instead of [name] or [matchingRatingsName].
  String get displayName => name ?? matchingRatingsName;

  /// Specific member numbers to match.
  List<String> memberNumbers = [];

  /// Specific classification names to match.
  List<String> classificationNames = [];

  /// Specific age category names to match.
  List<String> ageCategoryNames = [];

  /// Whether to only match female shooters.
  bool femaleOnly = false;

  /// A few names of ratings that match this set.
  List<MatchingRatingName> matchingRatingNames = [];

  DateTime created;
  DateTime updated;
  DateTime lastApplied;

  /// A default name for the rating set, used when [name] is unset.
  String get matchingRatingsName {
    if(matchingRatingNames.isEmpty) {
      if(memberNumbers.isNotEmpty) {
        var numbers = memberNumbers.take(3).join(", ");
        if(memberNumbers.length > 3) {
          numbers += ", ...";
        }
        return "$numbers";
      }
      else {
        return "(no matched ratings)";
      }
    }
    else {
      var names = matchingRatingNames.take(3).join(", ");
      if(matchingRatingNames.length > 3) {
        names += ", ...";
      }
      return names;
    }
  }

  void cleanMatchingNames() {
    List<MatchingRatingName> newMatchingRatingNames = [];
    for(var entry in matchingRatingNames) {
      if(memberNumbers.contains(entry.memberNumber)) {
        newMatchingRatingNames.add(entry);
      }
    }
    matchingRatingNames = newMatchingRatingNames;
  }

  bool matches(ShooterRating rating) {
    if(femaleOnly && !rating.female) {
      return false;
    }
    if(classificationNames.isNotEmpty && !classificationNames.contains(rating.lastClassification?.name)) {
      return false;
    }
    if(ageCategoryNames.isNotEmpty && !ageCategoryNames.contains(rating.ageCategory?.name)) {
      return false;
    }
    if(memberNumbers.isNotEmpty && !rating.knownMemberNumbers.any((n) => memberNumbers.contains(n))) {
      return false;
    }

    var name = rating.name;
    if(matchingRatingNames.length < 5 && !matchingRatingNames.contains(name)) {
      matchingRatingNames = [...matchingRatingNames, MatchingRatingName.fromRating(rating)];
    }
    lastApplied = DateTime.now();
    return true;
  }

  RatingSet({
    this.name,
    this.memberNumbers = const [],
    this.classificationNames = const [],
    this.ageCategoryNames = const [],
    this.femaleOnly = false,
    required this.created,
    required this.updated,
    required this.lastApplied,
  });

  RatingSet.create({
    this.name,
    this.memberNumbers = const [],
    this.classificationNames = const [],
    this.ageCategoryNames = const [],
    this.femaleOnly = false,
    DateTime? created,
    DateTime? updated,
    DateTime? lastApplied,
  }) : this.created = created ?? DateTime.now(),
    this.updated = updated ?? created ?? DateTime.now(),
    this.lastApplied = lastApplied ?? DateTime(1976, 5, 24);
}

@embedded
class MatchingRatingName {
  String name = "";
  String memberNumber = "";

  MatchingRatingName({this.name = "", this.memberNumber = ""});
  MatchingRatingName.fromRating(ShooterRating rating) : name = rating.name, memberNumber = rating.memberNumber;

  @override
  String toString() {
    return "$name";
  }
}
