/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "package:collection/collection.dart";
import "package:shooting_sports_analyst/data/database/schema/ratings.dart";
import "package:shooting_sports_analyst/data/ranking/invitational/invitation_match.dart";
import "package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart";
import "package:shooting_sports_analyst/data/sport/model.dart";
import "package:shooting_sports_analyst/util.dart";

class Invitation {
  final List<RatingGroup> groups;
  ShooterRating rating;
  final List<RelativeMatchScore> relativeMatchScores;
  final List<ShootingMatch> earnedAtMatches;
  final List<InvitationMatch> matchCriteria;
  final List<RatingGroup> earnedByRatings = [];
  bool fallbackSlot;
  bool reservedSlot;

  Invitation({
    required this.groups,
    required this.rating,
    List<RelativeMatchScore>? relativeMatchScores,
    List<ShootingMatch>? earnedAtMatches,
    List<InvitationMatch>? matchCriteria,
    required this.fallbackSlot,
    required this.reservedSlot,
  }) : relativeMatchScores = relativeMatchScores ?? [],
       earnedAtMatches = earnedAtMatches ?? [],
       matchCriteria = matchCriteria ?? [];

  Map<String, dynamic> toJson() {
    return {
      "memberNumber": rating.memberNumber,
      "name": rating.name,
      "email": rating.email ?? "",
      "groups": groups.map((g) => g.name).toList(),
      "rating": double.tryParse(rating.formattedRating) ?? 0,
      "fallbackSlot": fallbackSlot,
      "reservedSlot": reservedSlot,
      "matchInvitations": earnedAtMatches.mapIndexed((i, match) => {
        "matchName": match.name,
        "matchDate": programmerYmdFormat.format(match.date),
        "group": relativeMatchScores[i].shooter.division?.name,
        "place": relativeMatchScores[i].place,
        "percentage": double.tryParse(relativeMatchScores[i].ratio.asPercentage()) ?? 0,
        "matchCriterion": matchCriteria[i].toJson(),
      }).toList(),
      "ratingInvitations": earnedByRatings.map((g) => g.name).toList(),
    };
  }
}
