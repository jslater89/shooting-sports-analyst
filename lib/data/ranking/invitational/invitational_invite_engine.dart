/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "dart:convert";
import "dart:math";

import "package:collection/collection.dart";
import "package:shooting_sports_analyst/data/database/analyst_database.dart";
import "package:shooting_sports_analyst/data/database/match/rating_project_database.dart";
import "package:shooting_sports_analyst/data/database/schema/ratings.dart";
import "package:shooting_sports_analyst/data/ranking/invitational/invitation.dart";
import "package:shooting_sports_analyst/data/ranking/invitational/invitation_match.dart";
import "package:shooting_sports_analyst/data/ranking/invitational/invitational_invite_config.dart";
import "package:shooting_sports_analyst/data/ranking/model/rating_system.dart";
import "package:shooting_sports_analyst/data/sport/sport.dart";
import "package:shooting_sports_analyst/logger.dart";
import "package:shooting_sports_analyst/util.dart";

final _log = SSALogger("InvitationalInviteEngine");

typedef InvitationalInviteProgressCallback = void Function(int current, int total);

class InvitationalInviteResult {
  final InvitationalInviteConfig config;
  final List<Invitation> invitations;
  final Map<RatingGroup, List<Invitation>> invitationsByGroup;
  final Map<RatingGroup, List<Invitation>> ladyInvitationsByGroup;
  final Map<RatingGroup, List<Invitation>> juniorInvitationsByGroup;
  final Map<RatingGroup, List<Invitation>> seniorInvitationsByGroup;
  final List<RatingGroup> groups;
  final Map<RatingGroup, int> slotsByGroup;
  final Map<RatingGroup, int> filledSlotsByGroup;
  final Map<RatingGroup, int> maximumSlotsByGroup;
  final bool ladySlots;
  final bool juniorSlots;
  final bool seniorSlots;
  final bool combineJuniorSeniorSlots;
  final bool includeEmails;
  final List<String> warnings;

  InvitationalInviteResult({
    required this.config,
    required this.invitations,
    required this.invitationsByGroup,
    required this.ladyInvitationsByGroup,
    required this.juniorInvitationsByGroup,
    required this.seniorInvitationsByGroup,
    required this.groups,
    required this.slotsByGroup,
    required this.filledSlotsByGroup,
    required this.maximumSlotsByGroup,
    required this.ladySlots,
    required this.juniorSlots,
    required this.seniorSlots,
    required this.combineJuniorSeniorSlots,
    required this.includeEmails,
    required this.warnings,
  });

  bool get anyReservedSlots => ladySlots || juniorSlots || seniorSlots;

  String toCsv() {
    final lines = <String>[];
    final headers = [
      "Fallback",
      if(ladySlots) "Lady",
      if(juniorSlots) "Junior",
      if(seniorSlots) "Senior",
      if(anyReservedSlots) "Reserved",
      "Member#",
      "Name",
      if(includeEmails) "Email",
      "Group",
      "Rating",
      "MatchName",
      "EarnedDate",
      "EarnedPlace",
      "EarnedPercent",
    ];
    lines.add(headers.join(","));

    for(var group in groups) {
      var invitationsForGroup = invitationsByGroup[group];
      if(invitationsForGroup == null) {
        continue;
      }
      for(var invitation in invitationsForGroup) {
        final buffer = StringBuffer();
        final match = invitation.earnedAtMatches.firstOrNull;
        buffer.write("${invitation.fallbackSlot ? "Y" : "N"},");
        if(ladySlots) {
          buffer.write("${invitation.rating.female ? "Y" : "N"},");
        }
        if(juniorSlots) {
          buffer.write("${invitation.rating.ageCategory?.isJunior == true ? "Y" : "N"},");
        }
        if(seniorSlots) {
          buffer.write("${invitation.rating.ageCategory?.isSenior == true ? "Y" : "N"},");
        }
        if(anyReservedSlots) {
          buffer.write("${invitation.reservedSlot ? "Y" : "N"},");
        }
        buffer.write("${invitation.rating.memberNumber},");
        buffer.write('"${invitation.rating.name}",');
        if(includeEmails) {
          buffer.write("${invitation.rating.email ?? ""},");
        }
        buffer.write("${invitation.groups.map((g) => g.name).sorted().join("|")},");
        if(invitation.earnedAtMatches.isNotEmpty) {
          buffer.write("Match slot,");
        }
        else {
          buffer.write("${invitation.rating.formattedRating},");
        }
        buffer.write('"${match?.name ?? "Elo slot"}",');
        buffer.write("${match?.date != null ? programmerYmdFormat.format(match!.date) : "Elo slot"},");
        buffer.write("${invitation.relativeMatchScores.firstOrNull?.place ?? "Elo slot"},");
        buffer.write("${invitation.relativeMatchScores.firstOrNull?.ratio.asPercentage() ?? "Elo slot"}");
        lines.add(buffer.toString());
      }
    }
    return lines.join("\n");
  }

  String toJsonString() {
    final encoder = JsonEncoder.withIndent("  ");
    return encoder.convert(invitations.map((i) => i.toJson()).toList());
  }
}

class InvitationalInviteEngine {
  Future<Result<InvitationalInviteResult, StringError>> generate({
    required AnalystDatabase db,
    required DbRatingProject project,
    required InvitationalInviteConfig config,
    InvitationalInviteProgressCallback? onProgress,
  }) async {
    if(!project.dbGroups.isLoaded) {
      await project.dbGroups.load();
    }
    final allGroups = project.groups;
    final warnings = <String>[];

    final groups = <RatingGroup>[];
    final Map<RatingGroup, int> slotsByGroup = {};
    final Map<RatingGroup, int> ladySlotsByGroup = {};
    final Map<RatingGroup, int> juniorSlotsByGroup = {};
    final Map<RatingGroup, int> seniorSlotsByGroup = {};
    final Map<RatingGroup, int> juniorSeniorSlotsByGroup = {};

    for(final key in config.groupKeys) {
      final group = findRatingGroup(allGroups, key);
      if(group == null) {
        warnings.add("Could not find rating group matching key \"$key\"");
        continue;
      }
      final slotCount = config.slotsByGroup[key];
      if(slotCount == null) {
        warnings.add("slotsByGroup must define an integer slot count for group key \"$key\"");
        continue;
      }
      groups.add(group);
      slotsByGroup[group] = slotCount;

      if(config.ladySlots) {
        ladySlotsByGroup[group] = config.reservedLadySlotsByGroup[key] ?? 0;
      }
      if(config.combineAgeSlots) {
        juniorSeniorSlotsByGroup[group] = config.reservedJuniorSeniorSlotsByGroup[key] ?? 0;
      }
      else {
        if(config.juniorSlots) {
          juniorSlotsByGroup[group] = config.reservedJuniorSlotsByGroup[key] ?? 0;
        }
        if(config.seniorSlots) {
          seniorSlotsByGroup[group] = config.reservedSeniorSlotsByGroup[key] ?? 0;
        }
      }
    }

    if(groups.isEmpty) {
      return Result.err(StringError("No valid groups resolved from config."));
    }

    final invitationMatches = config.invitationMatches.where((m) => m.hasIdentification).toList();
    if(invitationMatches.isEmpty) {
      return Result.err(StringError("No valid invitationMatches entries defined in config."));
    }
    if(invitationMatches.length < config.invitationMatches.length) {
      warnings.add("Skipped ${config.invitationMatches.length - invitationMatches.length} finish-order rules with no match identification.");
    }

    final resolvedExcludedRules = <_ResolvedExcludedGroupsRule>[];
    for(final rule in config.excludedGroups) {
      if(!rule.hasIdentification) {
        warnings.add("Skipped an excluded-groups rule with no match identification.");
        continue;
      }
      final excludedGroups = <RatingGroup>[];
      for(final key in rule.groupKeys) {
        final group = findRatingGroup(allGroups, key);
        if(group == null) {
          warnings.add("excludedGroups: could not find rating group for key \"$key\"; skipping.");
          continue;
        }
        excludedGroups.add(group);
      }
      if(excludedGroups.isEmpty) {
        warnings.add("excludedGroups entry has no resolvable groups; skipping.");
        continue;
      }
      resolvedExcludedRules.add(_ResolvedExcludedGroupsRule(
        rule: rule,
        groups: excludedGroups,
      ));
    }

    final Map<RatingGroup, int> maximumSlotsByGroup = {
      for(final group in groups)
        group: (slotsByGroup[group]! / config.takeRate).round(),
    };

    _log.i("Slots by group: ${slotsByGroup.entries.map((e) => "${e.key.name}: ${e.value}").join(", ")}");
    _log.i("Take rate: ${config.takeRate}");
    _log.i("Maximum slots by group: ${maximumSlotsByGroup.entries.map((e) => "${e.key.name}: ${e.value}").join(", ")}");

    final sport = project.sport;
    final juniorCategories = sport.ageCategories.values.where((c) => c.isJunior).toList();
    final seniorCategories = sport.ageCategories.values.where((c) => c.isSenior).toList();
    if(config.juniorSlots && juniorCategories.isEmpty) {
      warnings.add("Junior reserved slots are enabled, but ${sport.name} has no junior age categories (maximum age 21 or under).");
    }
    if(config.seniorSlots && seniorCategories.isEmpty) {
      warnings.add("Senior reserved slots are enabled, but ${sport.name} has no senior age categories (minimum age 50 or over).");
    }

    Map<RatingGroup, int> filledSlotsByGroup = {
      for(var group in groups) group: 0,
    };

    List<Invitation> invitations = [];
    Map<RatingGroup, List<Invitation>> invitationsByGroup = {
      for(var group in groups) group: [],
    };
    Map<RatingGroup, List<Invitation>> ladyInvitations = {
      for(var group in groups) group: [],
    };
    Map<RatingGroup, List<Invitation>> juniorInvitations = {
      for(var group in groups) group: [],
    };
    Map<RatingGroup, List<Invitation>> seniorInvitations = {
      for(var group in groups) group: [],
    };
    Map<String, Invitation> invitationsByMemberNumber = {};
    final reservedOverflowInvitations = <Invitation>{};

    final Map<int, List<InvitationMatch>> invitationMatchesByPriority = {};
    for(final im in invitationMatches) {
      invitationMatchesByPriority.putIfAbsent(im.priority, () => []).add(im);
    }
    final prioritiesDescending = invitationMatchesByPriority.keys.toList()..sort((a, b) => b.compareTo(a));

    final ratingSystem = project.settings.algorithm;

    final matchPointers = [...project.matchPointers];
    matchPointers.sort((a, b) {
      final aDate = a.date ?? practicalShootingZeroDate;
      final bDate = b.date ?? practicalShootingZeroDate;
      return bDate.compareTo(aDate);
    });

    final reservedPasses = <_ReservedPass>[
      if(config.ladySlots) _ReservedPass.lady(),
      if(config.combineAgeSlots && (juniorCategories.isNotEmpty || seniorCategories.isNotEmpty))
        _ReservedPass.combinedAge([...juniorCategories, ...seniorCategories])
      else ...[
        if(config.juniorSlots && juniorCategories.isNotEmpty) _ReservedPass.junior(juniorCategories),
        if(config.seniorSlots && seniorCategories.isNotEmpty) _ReservedPass.senior(seniorCategories),
      ],
    ];

    for(final rule in invitationMatches) {
      if(rule.scope == InvitationMatchScope.lady && !config.ladySlots) {
        warnings.add("Finish-order rule \"${rule.displayLabel}\" is lady-scoped, but lady slots are disabled; it will not run.");
      }
      else if(rule.scope == InvitationMatchScope.junior && !config.juniorSlots) {
        warnings.add("Finish-order rule \"${rule.displayLabel}\" is junior-scoped, but junior slots are disabled; it will not run.");
      }
      else if(rule.scope == InvitationMatchScope.senior && !config.seniorSlots) {
        warnings.add("Finish-order rule \"${rule.displayLabel}\" is senior-scoped, but senior slots are disabled; it will not run.");
      }
      else if(rule.scope == InvitationMatchScope.categories && !config.anyReservedSlots) {
        warnings.add("Finish-order rule \"${rule.displayLabel}\" is categories-scoped, but no reserved slots are enabled; it will not run.");
      }
    }

    int totalSteps = 0;
    for(final priority in prioritiesDescending) {
      final rulesAtPriority = invitationMatchesByPriority[priority]!;
      final generalRules = rulesAtPriority.where((r) => r.scope.appliesToGeneralPass).toList();
      var passesForPriority = generalRules.isNotEmpty ? 1 : 0;
      for(final pass in reservedPasses) {
        if(rulesAtPriority.any((r) => r.scope.appliesToReservedPass(pass.kind))) {
          passesForPriority += 1;
        }
      }
      totalSteps += matchPointers.length * passesForPriority;
    }
    var currentStep = 0;

    Future<void> runMatchPass({
      required List<InvitationMatch> matchesAtPriority,
      required MatchPointer pointer,
      required _ReservedPass pass,
    }) async {
      if(matchesAtPriority.isEmpty) {
        return;
      }
      await _getMatchInvitations(
        combinedScoringForMultiDivisionGroups: config.combinedScoringForMultiDivisionGroups,
        matchesAtPriority: matchesAtPriority,
        pointer: pointer,
        db: db,
        project: project,
        ratingSystem: ratingSystem,
        maximumSlotsByGroup: maximumSlotsByGroup,
        filledSlotsByGroup: filledSlotsByGroup,
        excludedGroupsRules: resolvedExcludedRules,
        groups: groups,
        pass: pass,
        juniorCategories: juniorCategories,
        seniorCategories: seniorCategories,
        invitationsByMemberNumber: invitationsByMemberNumber,
        invitations: invitations,
        invitationsByGroup: invitationsByGroup,
        ladyInvitationsByGroup: ladyInvitations,
        juniorInvitationsByGroup: juniorInvitations,
        seniorInvitationsByGroup: seniorInvitations,
      );
      currentStep += 1;
      onProgress?.call(currentStep, totalSteps);
    }

    for(final priority in prioritiesDescending) {
      final matchesAtPriority = invitationMatchesByPriority[priority]!;
      final generalRules = matchesAtPriority.where((r) => r.scope.appliesToGeneralPass).toList();
      for(var pointer in matchPointers) {
        if(generalRules.isNotEmpty) {
          await runMatchPass(
            matchesAtPriority: generalRules,
            pointer: pointer,
            pass: const _ReservedPass.general(),
          );
        }
        for(final pass in reservedPasses) {
          final scopedRules = matchesAtPriority
              .where((r) => r.scope.appliesToReservedPass(pass.kind))
              .toList();
          if(scopedRules.isEmpty) {
            continue;
          }
          await runMatchPass(
            matchesAtPriority: scopedRules,
            pointer: pointer,
            pass: pass,
          );
        }
      }
    }

    for(var group in groups) {
      var ratings = project.getRatingsSync(group);
      if(ratings.isErr()) {
        warnings.add("Error getting ratings for group ${group.name}: ${ratings.unwrapErr()}");
        continue;
      }
      final ratingsList = ratings.unwrap();

      List<Invitation> ratingFill({
        required bool reserved,
        required InvitationPassCategory ratingSource,
        required bool Function(DbShooterRating rating) matches,
        required int neededSlots,
      }) {
        return _getRatingInvitations(
          ratingSystem: ratingSystem,
          ratings: ratingsList,
          group: group,
          reserved: reserved,
          ratingSource: ratingSource,
          matches: matches,
          activeSince: config.activeSince,
          neededSlots: neededSlots,
          filledSlotsByGroup: filledSlotsByGroup,
          invitationsByMemberNumber: invitationsByMemberNumber,
          invitations: invitations,
          invitationsByGroup: invitationsByGroup,
          ladyInvitationsByGroup: ladyInvitations,
          juniorInvitationsByGroup: juniorInvitations,
          seniorInvitationsByGroup: seniorInvitations,
          multipleDivisionRatingQualification: config.multipleDivisionRatingQualification,
        );
      }

      void fillReservedFloor({
        required int reservedCount,
        required InvitationPassCategory ratingSource,
        required int Function() currentCount,
        required bool Function(DbShooterRating rating) matches,
      }) {
        final neededFloor = reservedCount - currentCount();
        if(neededFloor > 0) {
          ratingFill(
            reserved: true,
            ratingSource: ratingSource,
            matches: matches,
            neededSlots: neededFloor,
          );
        }
      }

      void fillReservedOverflow({
        required int reservedCount,
        required InvitationPassCategory ratingSource,
        required int Function() currentCount,
        required bool Function(DbShooterRating rating) matches,
      }) {
        final inviteTarget = (reservedCount / config.takeRate).round();
        final remaining = maximumSlotsByGroup[group]! - filledSlotsByGroup[group]!;
        final neededOverflow = min(inviteTarget - currentCount(), remaining);
        if(neededOverflow > 0) {
          reservedOverflowInvitations.addAll(ratingFill(
            reserved: false,
            ratingSource: ratingSource,
            matches: matches,
            neededSlots: neededOverflow,
          ));
        }
      }

      if(config.ladySlots) {
        fillReservedFloor(
          reservedCount: ladySlotsByGroup[group] ?? 0,
          ratingSource: InvitationPassCategory.lady,
          currentCount: () => ladyInvitations[group]!.length,
          matches: (r) => r.female,
        );
      }

      if(config.combineAgeSlots) {
        fillReservedFloor(
          reservedCount: juniorSeniorSlotsByGroup[group] ?? 0,
          ratingSource: InvitationPassCategory.age,
          currentCount: () => <Invitation>{
            ...juniorInvitations[group]!,
            ...seniorInvitations[group]!,
          }.length,
          matches: (r) => r.ageCategory?.isJunior == true || r.ageCategory?.isSenior == true,
        );
      }
      else {
        if(config.juniorSlots) {
          fillReservedFloor(
            reservedCount: juniorSlotsByGroup[group] ?? 0,
            ratingSource: InvitationPassCategory.junior,
            currentCount: () => juniorInvitations[group]!.length,
            matches: (r) => r.ageCategory?.isJunior == true,
          );
        }
        if(config.seniorSlots) {
          fillReservedFloor(
            reservedCount: seniorSlotsByGroup[group] ?? 0,
            ratingSource: InvitationPassCategory.senior,
            currentCount: () => seniorInvitations[group]!.length,
            matches: (r) => r.ageCategory?.isSenior == true,
          );
        }
      }

      if(config.ladySlots) {
        fillReservedOverflow(
          reservedCount: ladySlotsByGroup[group] ?? 0,
          ratingSource: InvitationPassCategory.lady,
          currentCount: () => ladyInvitations[group]!.length,
          matches: (r) => r.female,
        );
      }

      if(config.combineAgeSlots) {
        fillReservedOverflow(
          reservedCount: juniorSeniorSlotsByGroup[group] ?? 0,
          ratingSource: InvitationPassCategory.age,
          currentCount: () => <Invitation>{
            ...juniorInvitations[group]!,
            ...seniorInvitations[group]!,
          }.length,
          matches: (r) => r.ageCategory?.isJunior == true || r.ageCategory?.isSenior == true,
        );
      }
      else {
        if(config.juniorSlots) {
          fillReservedOverflow(
            reservedCount: juniorSlotsByGroup[group] ?? 0,
            ratingSource: InvitationPassCategory.junior,
            currentCount: () => juniorInvitations[group]!.length,
            matches: (r) => r.ageCategory?.isJunior == true,
          );
        }
        if(config.seniorSlots) {
          fillReservedOverflow(
            reservedCount: seniorSlotsByGroup[group] ?? 0,
            ratingSource: InvitationPassCategory.senior,
            currentCount: () => seniorInvitations[group]!.length,
            matches: (r) => r.ageCategory?.isSenior == true,
          );
        }
      }

      final neededSlots = maximumSlotsByGroup[group]! - filledSlotsByGroup[group]!;
      ratingFill(
        reserved: false,
        ratingSource: InvitationPassCategory.general,
        matches: (_) => true,
        neededSlots: neededSlots,
      );
    }

    for(var group in groups) {
      var invitationsForGroup = invitationsByGroup[group];
      if(invitationsForGroup == null || invitationsForGroup.isEmpty) {
        continue;
      }

      var sortedInvitations = invitationsForGroup.sorted((a, b) {
        if(a.earnedAtMatches.isNotEmpty && b.earnedAtMatches.isEmpty) {
          return -1;
        }
        else if(a.earnedAtMatches.isEmpty && b.earnedAtMatches.isNotEmpty) {
          return 1;
        }
        else {
          return b.rating.rating.compareTo(a.rating.rating);
        }
      });

      int firstCutSlots = slotsByGroup[group]!;
      int firstCutIndex = min(firstCutSlots - 1, sortedInvitations.length - 1);
      if(firstCutIndex < 0) {
        invitationsByGroup[group] = sortedInvitations;
        continue;
      }

      double cutoffRating = sortedInvitations[firstCutIndex].rating.rating;

      final protectedReserved = <Invitation>{};
      void protectBelowCutoff(Iterable<Invitation> reserved) {
        for(var invitation in reserved) {
          if(reservedOverflowInvitations.contains(invitation)) {
            continue;
          }
          if(invitation.rating.rating < cutoffRating && protectedReserved.add(invitation)) {
            invitation.fallbackSlot = false;
            firstCutSlots--;
          }
        }
      }

      if(config.ladySlots) {
        protectBelowCutoff(ladyInvitations[group] ?? const []);
      }
      if(config.combineAgeSlots) {
        protectBelowCutoff(juniorInvitations[group] ?? const []);
        protectBelowCutoff(seniorInvitations[group] ?? const []);
      }
      else {
        if(config.juniorSlots) {
          protectBelowCutoff(juniorInvitations[group] ?? const []);
        }
        if(config.seniorSlots) {
          protectBelowCutoff(seniorInvitations[group] ?? const []);
        }
      }

      for(var (i, invitation) in sortedInvitations.indexed) {
        if(protectedReserved.contains(invitation)) {
          continue;
        }
        if(i < firstCutSlots) {
          invitation.fallbackSlot = false;
        }
        else {
          invitation.fallbackSlot = true;
        }
      }

      invitationsByGroup[group] = sortedInvitations;
    }

    _log.i("Total invitations after rating slots: ${invitations.length}");

    return Result.ok(InvitationalInviteResult(
      config: config,
      invitations: invitations,
      invitationsByGroup: invitationsByGroup,
      ladyInvitationsByGroup: ladyInvitations,
      juniorInvitationsByGroup: juniorInvitations,
      seniorInvitationsByGroup: seniorInvitations,
      groups: groups,
      slotsByGroup: slotsByGroup,
      filledSlotsByGroup: filledSlotsByGroup,
      maximumSlotsByGroup: maximumSlotsByGroup,
      ladySlots: config.ladySlots,
      juniorSlots: config.juniorSlots,
      seniorSlots: config.seniorSlots,
      combineJuniorSeniorSlots: config.combineAgeSlots,
      includeEmails: config.includeEmails,
      warnings: warnings,
    ));
  }

  List<Invitation> _getRatingInvitations({
    required RatingSystem ratingSystem,
    required List<DbShooterRating> ratings,
    required RatingGroup group,
    required bool reserved,
    required InvitationPassCategory ratingSource,
    required bool Function(DbShooterRating rating) matches,
    required DateTime? activeSince,
    required int neededSlots,
    required Map<RatingGroup, int> filledSlotsByGroup,
    required Map<String, Invitation> invitationsByMemberNumber,
    required List<Invitation> invitations,
    required Map<RatingGroup, List<Invitation>> invitationsByGroup,
    required Map<RatingGroup, List<Invitation>> ladyInvitationsByGroup,
    required Map<RatingGroup, List<Invitation>> juniorInvitationsByGroup,
    required Map<RatingGroup, List<Invitation>> seniorInvitationsByGroup,
    required bool multipleDivisionRatingQualification,
  }) {
    if(neededSlots <= 0) {
      return [];
    }

    var ratingsList = [...ratings];
    ratingsList.retainWhere((r) {
      final dateInRange = activeSince == null || r.lastSeen.isAfter(activeSince);
      return dateInRange && r.hasRatedHistory && matches(r);
    });
    ratingsList.sort((a, b) => b.rating.compareTo(a.rating));

    final added = <Invitation>[];
    for(var rating in ratingsList) {
      bool foundExistingInvitation = false;
      for(var number in rating.allPossibleMemberNumbers) {
        final existingInvitation = invitationsByMemberNumber[number];
        if(existingInvitation != null) {
          foundExistingInvitation = true;

          if(multipleDivisionRatingQualification) {
            existingInvitation.groups.addIfMissing(group);
            existingInvitation.addRatingQualification(group, ratingSource);
          }
          break;
        }
      }
      if(foundExistingInvitation) {
        continue;
      }

      var invitation = Invitation(groups: [group], rating: ratingSystem.wrapDbRating(rating), fallbackSlot: false, reservedSlot: reserved);
      invitation.addRatingQualification(group, ratingSource);
      invitations.add(invitation);
      invitationsByGroup.addToList(group, invitation);
      filledSlotsByGroup.increment(group);
      _recordCategoryInvitations(
        group: group,
        rating: rating,
        invitation: invitation,
        ladyInvitationsByGroup: ladyInvitationsByGroup,
        juniorInvitationsByGroup: juniorInvitationsByGroup,
        seniorInvitationsByGroup: seniorInvitationsByGroup,
      );
      added.add(invitation);
      for(var number in rating.allPossibleMemberNumbers) {
        invitationsByMemberNumber[number] = invitation;
      }

      if(added.length >= neededSlots) {
        break;
      }
    }
    return added;
  }

  Future<int> _getMatchInvitations({
    required bool combinedScoringForMultiDivisionGroups,
    required List<InvitationMatch> matchesAtPriority,
    required MatchPointer pointer,
    required AnalystDatabase db,
    required DbRatingProject project,
    required RatingSystem ratingSystem,
    required Map<RatingGroup, int> maximumSlotsByGroup,
    required Map<RatingGroup, int> filledSlotsByGroup,
    required List<_ResolvedExcludedGroupsRule> excludedGroupsRules,
    required List<RatingGroup> groups,
    required _ReservedPass pass,
    required List<AgeCategory> juniorCategories,
    required List<AgeCategory> seniorCategories,
    required Map<String, Invitation> invitationsByMemberNumber,
    required List<Invitation> invitations,
    required Map<RatingGroup, List<Invitation>> invitationsByGroup,
    required Map<RatingGroup, List<Invitation>> ladyInvitationsByGroup,
    required Map<RatingGroup, List<Invitation>> juniorInvitationsByGroup,
    required Map<RatingGroup, List<Invitation>> seniorInvitationsByGroup,
  }) async {
    int invitationsFromMatch = 0;
    for(var invitationMatch in matchesAtPriority) {
      if(!invitationMatch.pointerEligible(pointer)) {
        continue;
      }

      var dbMatchRes = await pointer.getDbMatch(db);
      if(dbMatchRes.isErr()) {
        continue;
      }

      var dbMatch = dbMatchRes.unwrap();

      var matchRes = dbMatch.hydrateSync(useCache: true);
      if(matchRes.isErr()) {
        continue;
      }

      var match = matchRes.unwrap();
      for(var group in groups) {
        bool isExcludedForGroup = false;
        for(final resolved in excludedGroupsRules) {
          if(resolved.rule.matches(name: match.name, sourceIds: match.sourceIds) && resolved.groups.contains(group)) {
            isExcludedForGroup = true;
            break;
          }
        }
        if(isExcludedForGroup) {
          continue;
        }

        if(filledSlotsByGroup[group]! >= maximumSlotsByGroup[group]!) {
          continue;
        }

        List<List<Division>> divisionGroups = [];
        if(combinedScoringForMultiDivisionGroups) {
          divisionGroups = [[...group.divisions]];
        }
        else {
          for(var d in group.divisions) {
            divisionGroups.add([d]);
          }
        }
        for(var divisionGroup in divisionGroups) {
          final ageCategories = pass.ageCategoriesForRule(
            invitationMatch.scope,
            juniorCategories: juniorCategories,
            seniorCategories: seniorCategories,
          );
          var relativeMatchScores = invitationMatch.getRelativeMatchScores(
            match,
            divisions: divisionGroup,
            lady: pass.lady,
            ageCategories: ageCategories,
          );
          if(relativeMatchScores.isNotEmpty) {
            for(var relativeMatchScore in relativeMatchScores) {
              var rating = db.maybeKnownShooterSync(project: project, group: group, memberNumber: relativeMatchScore.shooter.memberNumber);
              if(rating == null) {
                continue;
              }

              final passCategory = pass.passCategoryForRule(invitationMatch.scope);

              bool foundExistingInvitation = false;
              for(var number in rating.allPossibleMemberNumbers) {
                final existingInvitation = invitationsByMemberNumber[number];
                if(existingInvitation != null) {
                  existingInvitation.addMatchQualification(
                    group: group,
                    match: match,
                    score: relativeMatchScore,
                    criterion: invitationMatch,
                    passCategory: passCategory,
                  );
                  foundExistingInvitation = true;
                  break;
                }
              }
              if(foundExistingInvitation) {
                continue;
              }

              var invitation = Invitation(
                groups: [group],
                rating: ratingSystem.wrapDbRating(rating),
                relativeMatchScores: [relativeMatchScore],
                earnedAtMatches: [match],
                earnedMatchGroups: [group],
                matchCriteria: [invitationMatch],
                matchPassCategories: [passCategory],
                fallbackSlot: false,
                reservedSlot: pass.reserved,
              );
              invitations.add(invitation);
              invitationsByGroup.addToList(group, invitation);
              _recordCategoryInvitations(
                group: group,
                rating: rating,
                invitation: invitation,
                ladyInvitationsByGroup: ladyInvitationsByGroup,
                juniorInvitationsByGroup: juniorInvitationsByGroup,
                seniorInvitationsByGroup: seniorInvitationsByGroup,
              );
              invitationsFromMatch++;
              filledSlotsByGroup.increment(group);
              for(var number in rating.allPossibleMemberNumbers) {
                invitationsByMemberNumber[number] = invitation;
              }
            }
          }
        }
      }
    }
    return invitationsFromMatch;
  }

  void _recordCategoryInvitations({
    required RatingGroup group,
    required DbShooterRating rating,
    required Invitation invitation,
    required Map<RatingGroup, List<Invitation>> ladyInvitationsByGroup,
    required Map<RatingGroup, List<Invitation>> juniorInvitationsByGroup,
    required Map<RatingGroup, List<Invitation>> seniorInvitationsByGroup,
  }) {
    if(rating.female) {
      ladyInvitationsByGroup.addToList(group, invitation);
    }
    if(rating.ageCategory?.isJunior == true) {
      juniorInvitationsByGroup.addToList(group, invitation);
    }
    if(rating.ageCategory?.isSenior == true) {
      seniorInvitationsByGroup.addToList(group, invitation);
    }
  }
}

class _ReservedPass {
  final InvitationMatchPassKind kind;
  final bool lady;
  final List<AgeCategory>? ageCategories;

  const _ReservedPass.general()
      : kind = InvitationMatchPassKind.general,
        lady = false,
        ageCategories = null;

  const _ReservedPass.lady()
      : kind = InvitationMatchPassKind.lady,
        lady = true,
        ageCategories = null;

  _ReservedPass.junior(List<AgeCategory> categories)
      : kind = InvitationMatchPassKind.junior,
        lady = false,
        ageCategories = categories;

  _ReservedPass.senior(List<AgeCategory> categories)
      : kind = InvitationMatchPassKind.senior,
        lady = false,
        ageCategories = categories;

  _ReservedPass.combinedAge(List<AgeCategory> categories)
      : kind = InvitationMatchPassKind.combinedAge,
        lady = false,
        ageCategories = categories;

  bool get reserved => kind != InvitationMatchPassKind.general;

  /// Age categories for [getRelativeMatchScores], with combined-pass overrides by rule scope.
  List<AgeCategory>? ageCategoriesForRule(
    InvitationMatchScope scope, {
    required List<AgeCategory> juniorCategories,
    required List<AgeCategory> seniorCategories,
  }) {
    if(kind != InvitationMatchPassKind.combinedAge) {
      return ageCategories;
    }
    return switch(scope) {
      InvitationMatchScope.junior => juniorCategories,
      InvitationMatchScope.senior => seniorCategories,
      InvitationMatchScope.all || InvitationMatchScope.categories => ageCategories,
      InvitationMatchScope.general || InvitationMatchScope.lady => ageCategories,
    };
  }

  /// Effective pass category recorded on match qualifications for this pass + rule.
  InvitationPassCategory passCategoryForRule(InvitationMatchScope scope) {
    return switch(kind) {
      InvitationMatchPassKind.general => InvitationPassCategory.general,
      InvitationMatchPassKind.lady => InvitationPassCategory.lady,
      InvitationMatchPassKind.junior => InvitationPassCategory.junior,
      InvitationMatchPassKind.senior => InvitationPassCategory.senior,
      InvitationMatchPassKind.combinedAge => switch(scope) {
        InvitationMatchScope.junior => InvitationPassCategory.junior,
        InvitationMatchScope.senior => InvitationPassCategory.senior,
        _ => InvitationPassCategory.age,
      },
    };
  }
}

class _ResolvedExcludedGroupsRule {
  final ExcludedGroupsRule rule;
  final List<RatingGroup> groups;

  _ResolvedExcludedGroupsRule({
    required this.rule,
    required this.groups,
  });
}
