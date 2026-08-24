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
  final InvitationPassCategory passCategory;

  const InvitationMatchQualification({
    required this.group,
    required this.match,
    required this.score,
    required this.criterion,
    required this.passCategory,
  });
}

/// Which invite-engine pass produced a match or rating qualification.
enum InvitationPassCategory {
  general,
  lady,
  junior,
  senior,
  /// Combined junior+senior age leaderboard / rating pool.
  age;

  String get label => switch(this) {
    general => "General",
    lady => "Lady",
    junior => "Junior",
    senior => "Senior",
    age => "Age",
  };

  bool get isCategory => this != general;
}

/// One rating-fill qualification that earned or extended an invitation.
class InvitationRatingQualification {
  final RatingGroup group;
  final InvitationPassCategory source;

  const InvitationRatingQualification({
    required this.group,
    required this.source,
  });
}

class Invitation {
  final List<RatingGroup> groups;
  ShooterRating rating;
  final List<RelativeMatchScore> relativeMatchScores;
  final List<ShootingMatch> earnedAtMatches;
  final List<RatingGroup> earnedMatchGroups;
  final List<InvitationMatch> matchCriteria;
  final List<InvitationPassCategory> matchPassCategories;
  final List<InvitationRatingQualification> ratingQualifications = [];
  bool fallbackSlot;
  bool reservedSlot;

  Invitation({
    required this.groups,
    required this.rating,
    List<RelativeMatchScore>? relativeMatchScores,
    List<ShootingMatch>? earnedAtMatches,
    List<RatingGroup>? earnedMatchGroups,
    List<InvitationMatch>? matchCriteria,
    List<InvitationPassCategory>? matchPassCategories,
    required this.fallbackSlot,
    required this.reservedSlot,
  }) : relativeMatchScores = relativeMatchScores ?? [],
       earnedAtMatches = earnedAtMatches ?? [],
       earnedMatchGroups = earnedMatchGroups ?? [],
       matchCriteria = matchCriteria ?? [],
       matchPassCategories = matchPassCategories ?? [];

  /// Groups that earned a rating-fill qualification (order preserved).
  List<RatingGroup> get earnedByRatings => [
    for(final q in ratingQualifications) q.group,
  ];

  /// Records a rating-fill qualification for [group] if one is not already present.
  void addRatingQualification(RatingGroup group, InvitationPassCategory source) {
    if(ratingQualifications.any((q) => q.group == group)) {
      return;
    }
    ratingQualifications.add(InvitationRatingQualification(group: group, source: source));
  }

  /// Appends a match finish-order qualification.
  void addMatchQualification({
    required RatingGroup group,
    required ShootingMatch match,
    required RelativeMatchScore score,
    required InvitationMatch criterion,
    required InvitationPassCategory passCategory,
  }) {
    groups.addIfMissing(group);
    relativeMatchScores.add(score);
    earnedAtMatches.add(match);
    earnedMatchGroups.add(group);
    matchCriteria.add(criterion);
    matchPassCategories.add(passCategory);
  }

  /// Match qualifications with duplicate match/group/pass triples removed.
  ///
  /// The same match can legitimately qualify on both general and category passes;
  /// those are kept separately. Duplicate appends of the same triple are collapsed.
  List<InvitationMatchQualification> get deduplicatedMatchQualifications {
    final seen = <String>{};
    final qualifications = <InvitationMatchQualification>[];

    for(var i = 0; i < earnedAtMatches.length; i++) {
      final group = _groupForMatchQualificationIndex(i);
      if(group == null) {
        continue;
      }

      final passCategory = i < matchPassCategories.length
          ? matchPassCategories[i]
          : InvitationPassCategory.general;
      final key = _matchGroupPassDedupeKey(group, earnedAtMatches[i], passCategory);
      if(!seen.add(key)) {
        continue;
      }

      qualifications.add(InvitationMatchQualification(
        group: group,
        match: earnedAtMatches[i],
        score: relativeMatchScores[i],
        criterion: matchCriteria[i],
        passCategory: passCategory,
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

  static String _matchGroupPassDedupeKey(
    RatingGroup group,
    ShootingMatch match,
    InvitationPassCategory passCategory,
  ) {
    final matchPart = match.sourceIds.isNotEmpty
        ? match.sourceIds.sorted().join("|")
        : "${programmerYmdFormat.format(match.date)}|${match.name}";
    return "${group.name}|$matchPart|${passCategory.name}";
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
        "passCategory": qualification.passCategory.name,
        "matchCriterion": qualification.criterion.toJson(),
      }).toList(),
      "ratingInvitations": ratingQualifications.map((q) => {
        "ratingGroup": q.group.name,
        "source": q.source.name,
      }).toList(),
    };
  }
}
