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

/// One finish-order qualification that earned or extended an invitation.
class InvitationMatchQualification {
  final RatingGroup group;
  final ShootingMatch match;
  final RelativeMatchScore score;
  final InvitationMatch criterion;

  const InvitationMatchQualification({
    required this.group,
    required this.match,
    required this.score,
    required this.criterion,
  });
}

class Invitation {
  final List<RatingGroup> groups;
  ShooterRating rating;
  final List<RelativeMatchScore> relativeMatchScores;
  final List<ShootingMatch> earnedAtMatches;
  final List<RatingGroup> earnedMatchGroups;
  final List<InvitationMatch> matchCriteria;
  final List<RatingGroup> earnedByRatings = [];
  bool fallbackSlot;
  bool reservedSlot;

  Invitation({
    required this.groups,
    required this.rating,
    List<RelativeMatchScore>? relativeMatchScores,
    List<ShootingMatch>? earnedAtMatches,
    List<RatingGroup>? earnedMatchGroups,
    List<InvitationMatch>? matchCriteria,
    required this.fallbackSlot,
    required this.reservedSlot,
  }) : relativeMatchScores = relativeMatchScores ?? [],
       earnedAtMatches = earnedAtMatches ?? [],
       earnedMatchGroups = earnedMatchGroups ?? [],
       matchCriteria = matchCriteria ?? [];

  /// Match qualifications with duplicate match/group pairs removed.
  ///
  /// Reserved-pass reprocessing can append the same match qualification more than
  /// once; the detail view should show each match/group pair only once.
  List<InvitationMatchQualification> get deduplicatedMatchQualifications {
    final seen = <String>{};
    final qualifications = <InvitationMatchQualification>[];

    for(var i = 0; i < earnedAtMatches.length; i++) {
      final group = _groupForMatchQualificationIndex(i);
      if(group == null) {
        continue;
      }

      final key = _matchGroupDedupeKey(group, earnedAtMatches[i]);
      if(!seen.add(key)) {
        continue;
      }

      qualifications.add(InvitationMatchQualification(
        group: group,
        match: earnedAtMatches[i],
        score: relativeMatchScores[i],
        criterion: matchCriteria[i],
      ));
    }

    qualifications.sort((a, b) => b.match.date.compareTo(a.match.date));
    return qualifications;
  }

  RatingGroup? _groupForMatchQualificationIndex(int index) {
    if(index < earnedMatchGroups.length) {
      return earnedMatchGroups[index];
    }

    if(index >= relativeMatchScores.length) {
      return null;
    }

    final division = relativeMatchScores[index].shooter.division;
    if(division == null) {
      return null;
    }

    for(final group in groups) {
      if(group.divisions.contains(division)) {
        return group;
      }
    }
    return null;
  }

  static String _matchGroupDedupeKey(RatingGroup group, ShootingMatch match) {
    final matchPart = match.sourceIds.isNotEmpty
        ? match.sourceIds.sorted().join("|")
        : "${programmerYmdFormat.format(match.date)}|${match.name}";
    return "${group.name}|$matchPart";
  }

  Map<String, dynamic> toJson() {
    return {
      "memberNumber": rating.memberNumber,
      "name": rating.name,
      "email": rating.email ?? "",
      "groups": groups.map((g) => g.name).toList(),
      "rating": double.tryParse(rating.formattedRating) ?? 0,
      "fallbackSlot": fallbackSlot,
      "reservedSlot": reservedSlot,
      "matchInvitations": deduplicatedMatchQualifications.map((qualification) => {
        "matchName": qualification.match.name,
        "matchDate": programmerYmdFormat.format(qualification.match.date),
        "ratingGroup": qualification.group.name,
        "division": qualification.score.shooter.division?.name,
        "place": qualification.score.place,
        "percentage": double.tryParse(qualification.score.ratio.asPercentage()) ?? 0,
        "matchCriterion": qualification.criterion.toJson(),
      }).toList(),
      "ratingInvitations": earnedByRatings.map((g) => g.name).toList(),
    };
  }
}
