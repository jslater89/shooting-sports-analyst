import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:dart_console/src/console.dart';
import 'package:shooting_sports_analyst/console/repl.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/match/rating_project_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_system.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/uspsa.dart';
import 'package:shooting_sports_analyst/data/sport/model.dart';
import 'package:shooting_sports_analyst/util.dart';
import 'package:toml/toml.dart';

import 'base.dart';

class GenerateInvitationalInvitesCommand extends DbOneoffCommand {
  GenerateInvitationalInvitesCommand(super.db);

  @override
  final String key = "GI";
  @override
  final String title = "Generate Invitational Invites";

  @override
  List<MenuArgument> get arguments => [
        StringMenuArgument(
          label: "Config path",
          description: "Path to a TOML config file for invitations",
          required: true,
        ),
      ];

  @override
  Future<void> executor(Console console, List<MenuArgumentValue<dynamic>> arguments) async {
    final configPath = arguments[0].value as String;
    final configFile = File(configPath);
    if(!configFile.existsSync()) {
      console.print("Config file does not exist: ${configFile.path}");
      return;
    }

    TomlDocument doc;
    try {
      doc = await TomlDocument.load(configFile.path);
    }
    catch(e) {
      console.print("Failed to load TOML config: $e");
      return;
    }

    final Map<String, dynamic> config = doc.toMap();

    final String projectName = (config["projectName"] as String?) ?? "L2s Main";

    final project = await db.getRatingProjectByName(projectName);
    if(project == null) {
      console.print("Project not found: ${projectName}");
      return;
    }

    final allGroups = uspsaSport.builtinRatingGroupsProvider!.divisionRatingGroups;
    final List<dynamic>? configGroupKeys = config["groups"] as List<dynamic>?;
    if(configGroupKeys == null || configGroupKeys.isEmpty) {
      console.print("Config must define a non-empty \"groups\" array.");
      return;
    }

    // --- Parse groups, slots, and lady slots ---
    final bool ladySlots = (config["ladySlots"] as bool?) ?? false;
    final bool multipleDivisionRatingQualification = (config["multipleDivisionRatingQualification"] as bool?) ?? false;
    final bool includeEmails = (config["includeEmails"] as bool?) ?? false;

    final Map<dynamic, dynamic> rawSlotsByGroup =
        (config["slotsByGroup"] as Map?) ?? {};

    final Map<dynamic, dynamic> rawLadySlotsByGroup =
        (config["reservedLadySlotsByGroup"] as Map?) ?? {};

    final groups = <RatingGroup>[];
    final Map<RatingGroup, int> slotsByGroup = {};
    final Map<RatingGroup, int> ladySlotsByGroup = {};

    for(final dynamic keyDynamic in configGroupKeys) {
      if(keyDynamic is! String) {
        console.print("Group keys must be strings. Got: ${keyDynamic.runtimeType}");
        continue;
      }
      final key = keyDynamic;
      final group = findGroup(allGroups, key);
      if(group == null) {
        console.print("Could not find rating group matching key \"${key}\"");
        continue;
      }
      final dynamic slotCountDynamic = rawSlotsByGroup[key];
      if(slotCountDynamic is! int) {
        console.print("slotsByGroup must define an integer slot count for group key \"${key}\"");
        continue;
      }
      groups.add(group);
      slotsByGroup[group] = slotCountDynamic;

      if(ladySlots) {
        final dynamic ladySlotCountDynamic = rawLadySlotsByGroup[key];
        if(ladySlotCountDynamic is! int) {
          console.print("ladySlotsByGroup must define an integer slot count for group key \"${key}\"");
          continue;
        }
        ladySlotsByGroup[group] = ladySlotCountDynamic;
      }
    }

    if(groups.isEmpty) {
      console.print("No valid groups resolved from config.");
      return;
    }

    final double takeRate =
        (config["takeRate"] as num?)?.toDouble() ?? 0.6;


    DateTime? activeSince;
    final String? activeSinceStr = config["activeSince"] as String?;
    if(activeSinceStr != null) {
      try {
        activeSince = DateTime.parse(activeSinceStr);
      }
      catch(_) {
        console.print("Could not parse activeSince \"${activeSinceStr}\"; ignoring.");
      }
    }

    final Map<RatingGroup, int> maximumSlotsByGroup = {
      for(final group in groups)
        group: (slotsByGroup[group]! / takeRate).round(),
    };

    console.print("Slots by group: ${slotsByGroup.entries.map((e) => "${e.key.name}: ${e.value}").join(", ")}");
    console.print("Lady slots by group: ${ladySlotsByGroup.entries.map((e) => "${e.key.name}: ${e.value}").join(", ")}");
    console.print("Take rate: ${takeRate}");
    console.print("Maximum slots by group: ${maximumSlotsByGroup.entries.map((e) => "${e.key.name}: ${e.value}").join(", ")}");

    Map<RatingGroup, int> filledSlotsByGroup = {};
    for(var group in groups) {
      filledSlotsByGroup[group] = 0;
    }

    console.print("Groups: ${groups.map((g) => g.name).join(", ")}");

    // Excluded groups rules – skip specific groups for matches whose names
    // match configured patterns.
    final List<dynamic> rawExcludedGroups =
        (config["excludedGroups"] as List<dynamic>?) ?? [];

    final List<_ExcludedGroupsRule> excludedGroupsRules = [];
    for(final dynamic entry in rawExcludedGroups) {
      if(entry is! Map) {
        console.print("excludedGroups entries must be tables; got ${entry.runtimeType}");
        continue;
      }
      final Map<dynamic, dynamic> table = entry;
      final dynamic patternsDynamic = table["namePatterns"];
      if(patternsDynamic is! List) {
        console.print("excludedGroups entry missing \"namePatterns\" list; skipping.");
        continue;
      }
      final List<RegExp> namePatterns = patternsDynamic
          .whereType<String>()
          .map((s) => RegExp(s))
          .toList();
      if(namePatterns.isEmpty) {
        console.print("excludedGroups entry has empty \"namePatterns\"; skipping.");
        continue;
      }

      final dynamic groupsDynamic = table["groups"];
      if(groupsDynamic is! List) {
        console.print("excludedGroups entry missing \"groups\" list; skipping.");
        continue;
      }
      final List<RatingGroup> excludedGroups = [];
      for(final dynamic keyDynamic in groupsDynamic) {
        if(keyDynamic is! String) {
          console.print("excludedGroups group keys must be strings; got ${keyDynamic.runtimeType}");
          continue;
        }
        final group = findGroup(allGroups, keyDynamic);
        if(group == null) {
          console.print("excludedGroups: could not find rating group for key \"${keyDynamic}\"; skipping.");
          continue;
        }
        excludedGroups.add(group);
      }
      if(excludedGroups.isEmpty) {
        console.print("excludedGroups entry has no resolvable groups; skipping.");
        continue;
      }
      excludedGroupsRules.add(_ExcludedGroupsRule(
        namePatterns: namePatterns,
        groups: excludedGroups,
      ));
    }

    // A list of invitations to hand out.
    List<Invitation> invitations = [];
    Map<RatingGroup, List<Invitation>> invitationsByGroup = {};
    Map<RatingGroup, List<Invitation>> ladyInvitatations = {};
    for(var group in groups) {
      invitationsByGroup[group] = [];
      ladyInvitatations[group] = [];
    }
    Map<String, Invitation> invitationsByMemberNumber = {};

    final List<dynamic> rawInvitationMatches =
        (config["invitationMatches"] as List<dynamic>?) ?? [];

    final List<InvitationMatch> invitationMatches = [];
    for(final dynamic entry in rawInvitationMatches) {
      if(entry is Map) {
        final parsed = parseInvitationMatch(entry, console);
        if(parsed != null) {
          invitationMatches.add(parsed);
        }
      }
      else {
        console.print("invitationMatches entries must be tables; got ${entry.runtimeType}");
      }
    }

    if(invitationMatches.isEmpty) {
      console.print("No valid invitationMatches entries defined in config.");
      return;
    }

    final Map<int, List<InvitationMatch>> invitationMatchesByPriority = {};
    for(final im in invitationMatches) {
      invitationMatchesByPriority.putIfAbsent(im.priority, () => []).add(im);
    }
    final prioritiesDescending = invitationMatchesByPriority.keys.toList()..sort((a, b) => b.compareTo(a));

    final ratingSystem = project.settings.algorithm;

    /// Get slots from matches
    ///
    /// Higher priority rules run first; within each priority, matches are
    /// processed in reverse chronological order.
    final matchPointers = [...project.matchPointers];
    matchPointers.sort((a, b) => b.date!.compareTo(a.date!));

    for(final priority in prioritiesDescending) {
      final matchesAtPriority = invitationMatchesByPriority[priority]!;
      for(var pointer in matchPointers) {
        // First, add overall winners.
        await getMatchInvitations(
          matchesAtPriority: matchesAtPriority,
          pointer: pointer,
          db: db,
          project: project,
          ratingSystem: ratingSystem,
          maximumSlotsByGroup: maximumSlotsByGroup,
          filledSlotsByGroup: filledSlotsByGroup,
          excludedGroupsRules: excludedGroupsRules,
          groups: groups,
          ladySlots: ladySlots,
          lady: false,
          console: console,
          invitationsByMemberNumber: invitationsByMemberNumber,
          invitations: invitations,
          invitationsByGroup: invitationsByGroup,
          ladyInvitationsByGroup: ladyInvitatations,
        );

        // Second, go back and add lady winners if lady slots are
        // enabled and they haven't already been invited.
        if(ladySlots) {
          await getMatchInvitations(
            matchesAtPriority: matchesAtPriority,
            pointer: pointer,
            db: db,
            project: project,
            ratingSystem: ratingSystem,
            maximumSlotsByGroup: maximumSlotsByGroup,
            filledSlotsByGroup: filledSlotsByGroup,
            excludedGroupsRules: excludedGroupsRules,
            groups: groups,
            ladySlots: ladySlots,
            lady: true,
            console: console,
            invitationsByMemberNumber: invitationsByMemberNumber,
            invitations: invitations,
            invitationsByGroup: invitationsByGroup,
            ladyInvitationsByGroup: ladyInvitatations,
          );
        }
      }
    }

    console.print("Match slots by group: ${filledSlotsByGroup.entries.map((e) => "${e.key.name}: ${e.value}").join(", ")}");
    if(ladySlots) {
      console.print("Lady match slots by group: ${ladyInvitatations.entries.map((e) => "${e.key.name}: ${e.value.length}").join(", ")}");
    }

    for(var group in groups) {
      var ratings = project.getRatingsSync(group);
      if(ratings.isErr()) {
        console.print("Error getting ratings for group ${group.name}: ${ratings.unwrapErr()}");
        continue;
      }
      final ratingsList = ratings.unwrap();

      console.print("Match slots for group ${group.name}: ${filledSlotsByGroup[group]!}/${maximumSlotsByGroup[group]!}");
      console.print("Match invitations: ${invitationsByGroup[group]!.length}");

      if(ladySlots) {
        // If we're doing lady slots, and we have fewer in the group than reserved lady slots,
        // loop over ladies first until we have enough.
        int neededLadySlots = ladySlotsByGroup[group]! - ladyInvitatations[group]!.length;
        if(neededLadySlots > 0) {
          final ratingsAdded = getRatingInvitations(
            ratingSystem: ratingSystem,
            ratings: ratingsList,
            group: group,
            lady: true,
            console: console,
            activeSince: activeSince,
            neededSlots: neededLadySlots,
            filledSlotsByGroup: filledSlotsByGroup,
            invitationsByMemberNumber: invitationsByMemberNumber,
            invitations: invitations,
            invitationsByGroup: invitationsByGroup,
            ladyInvitationsByGroup: ladyInvitatations,
            multipleDivisionRatingQualification: multipleDivisionRatingQualification,
          );
          console.print("Added $ratingsAdded lady invites for group ${group.name}");
          console.print("Remaining required invites: ${maximumSlotsByGroup[group]! - filledSlotsByGroup[group]!}");
        }
      }

      final neededSlots = maximumSlotsByGroup[group]! - filledSlotsByGroup[group]!;
      final ratingsAdded = getRatingInvitations(
        ratingSystem: ratingSystem,
        ratings: ratingsList,
        group: group,
        lady: false,
        console: console,
        activeSince: activeSince,
        neededSlots: neededSlots,
        filledSlotsByGroup: filledSlotsByGroup,
        invitationsByMemberNumber: invitationsByMemberNumber,
        invitations: invitations,
        invitationsByGroup: invitationsByGroup,
        ladyInvitationsByGroup: ladyInvitatations,
        multipleDivisionRatingQualification: multipleDivisionRatingQualification,
      );
      console.print("Added $ratingsAdded invites for group ${group.name}");

      console.print("Filled ${filledSlotsByGroup[group]!}/${maximumSlotsByGroup[group]!} slots for group ${group.name}");
      console.print("Invitations by group: ${invitationsByGroup[group]!.length}\n");
    }

    // Handle main vs. fallback slots
    for(var group in groups) {
      var invitationsForGroup = invitationsByGroup[group];
      if(invitationsForGroup == null || invitationsForGroup.isEmpty) {
        continue;
      }

      console.print("Group ${group.name}: ${invitationsForGroup.length} invitations");

      var sortedInvitations = invitationsForGroup.sorted((a, b) {
        // Slots earned at matches should come first.
        if(a.earnedAtMatches.isNotEmpty && b.earnedAtMatches.isEmpty) {
          return -1;
        }
        else if(a.earnedAtMatches.isEmpty && b.earnedAtMatches.isNotEmpty) {
          return 1;
        }
        else {
          // Otherwise, sort by rating.
          return b.rating.rating.compareTo(a.rating.rating);
        }
      });

      int firstCutSlots = slotsByGroup[group]!;
      console.print("First cut slots: $firstCutSlots");

      int firstCutIndex = min(firstCutSlots - 1, sortedInvitations.length - 1);

      double cutoffRating = sortedInvitations[firstCutIndex].rating.rating;
      console.print("Cutoff rating: $cutoffRating\n");

      // If we're reserving lady slots, they're always non-fallback slots.
      List<Invitation> reservedLadyInvitations = [];
      if(ladySlots) {
        final groupLadies = ladyInvitatations[group] ?? [];
        for(var invitation in groupLadies) {

          // If this is not a first cut slot already, make it a first cut slot and
          // reduce the number of general first cut slots by 1.
          if(invitation.rating.rating < cutoffRating) {
            invitation.fallbackSlot = false;
            reservedLadyInvitations.add(invitation);
            firstCutSlots--;
          }
        }
      }

      // Assign main vs. fallback slots.
      for(var (i, invitation) in sortedInvitations.indexed) {
        if(reservedLadyInvitations.contains(invitation)) {
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

    console.print("Total invitations after rating slots: ${invitations.length}");

    final lines = <String>[];
    final String header;
    List<String> headers = [
      "Fallback",
      if(ladySlots) "Lady",
      if(ladySlots) "Reserved",
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
    header = headers.join(",");
    lines.add(header);

    // console.print(header);

    for(var group in groups) {
      var invitationsForGroup = invitationsByGroup[group];
      if(invitationsForGroup == null) {
        continue;
      }
      console.print("Group ${group.name}:");
      console.print("General invitations: ${invitationsForGroup.length - (ladyInvitatations[group]?.length ?? 0)}");
      console.print("Lady invitations: ${ladyInvitatations[group]?.length ?? 0}\n");
      for(var invitation in invitationsForGroup) {
        final buffer = StringBuffer();
        final match = invitation.earnedAtMatches.firstOrNull;
        buffer.write("${invitation.fallbackSlot ? "Y" : "N"},");
        if(ladySlots) {
          buffer.write("${invitation.rating.female ? "Y" : "N"},");
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
          buffer.write("${invitation.rating.formattedRating()},");
        }
        buffer.write('"${match?.name ?? "Elo slot"}",');
        buffer.write("${match?.date != null ? programmerYmdFormat.format(match!.date) : "Elo slot"},");
        buffer.write("${invitation.relativeMatchScores.firstOrNull?.place ?? "Elo slot"},");
        buffer.write("${invitation.relativeMatchScores.firstOrNull?.ratio.asPercentage() ?? "Elo slot"}");
        final line = buffer.toString();
        // console.print(line);
        lines.add(line);
      }
    }

    console.print("Writing ${lines.length} lines to file...");
    final csv = lines.join("\n");
    final file = File("/tmp/invitations.csv");
    file.writeAsStringSync(csv);

    List<dynamic> jsonInvitations = invitations.map((i) => i.toJson()).toList();
    final encoder = JsonEncoder.withIndent("  ");
    final json = encoder.convert(jsonInvitations);
    final jsonFile = File("/tmp/invitations.json");
    jsonFile.writeAsStringSync(json);

    console.print("Invitations written to ${file.path} and ${jsonFile.path}");
  }

  RatingGroup? findGroup(List<RatingGroup> allGroups, String key) {
    return allGroups.firstWhereOrNull((g) =>
          g.uuid == key ||
          g.uuid.contains(key) ||
          g.name.toLowerCase() == key.toLowerCase());
  }

  InvitationMatch? parseInvitationMatch(Map<dynamic, dynamic> raw, Console console) {
    final String? type = raw["type"] as String?;
    final String? namePatternStr = raw["namePattern"] as String?;
    if(namePatternStr == null) {
      console.print("invitationMatches entry is missing required \"namePattern\".");
      return null;
    }
    final RegExp namePattern = RegExp(namePatternStr);

    List<RegExp> patternsFromList(dynamic value) {
      if(value is List) {
        return value
            .whereType<String>()
            .map((s) => RegExp(s))
            .toList();
      }
      return [];
    }

    final additionalPatterns =
        patternsFromList(raw["additionalPatterns"]);
    final negativePatterns =
        patternsFromList(raw["negativePatterns"]);

    DateTime? afterDate;
    final String? afterDateStr = raw["afterDate"] as String?;
    if(afterDateStr != null) {
      try {
        afterDate = DateTime.parse(afterDateStr);
      }
      catch(_) {
        console.print("Could not parse afterDate \"${afterDateStr}\"; ignoring.");
      }
    }

    final int minimumCompetitors =
        (raw["minimumCompetitors"] as int?) ?? 0;

    final int priority = (raw["priority"] as int?) ?? 1;

    if(type == null || type == "topN") {
      final int? topN = raw["topN"] as int?;
      if(topN == null) {
        console.print("topN invitationMatches entry is missing \"topN\"; skipping.");
        return null;
      }
      return InvitationMatch.topN(
        namePattern: namePattern,
        additionalPatterns: additionalPatterns,
        negativePatterns: negativePatterns,
        afterDate: afterDate,
        topN: topN,
        minimumCompetitors: minimumCompetitors,
        priority: priority,
      );
    }
    else if(type == "aboveNPercent") {
      final num? aboveNPercentRaw = raw["aboveNPercent"] as num?;
      if(aboveNPercentRaw == null) {
        console.print("aboveNPercent invitationMatches entry is missing \"aboveNPercent\"; skipping.");
        return null;
      }
      final double aboveNPercent = aboveNPercentRaw.toDouble();
      return InvitationMatch.aboveNPercent(
        namePattern: namePattern,
        additionalPatterns: additionalPatterns,
        negativePatterns: negativePatterns,
        afterDate: afterDate,
        aboveNPercent: aboveNPercent,
        minimumCompetitors: minimumCompetitors,
        priority: priority,
      );
    }
    else if(type == "either") {
      final int? topN = raw["topN"] as int?;
      final num? aboveNPercentRaw = raw["aboveNPercent"] as num?;
      if(topN == null || aboveNPercentRaw == null) {
        console.print("either invitationMatches entry must define both \"topN\" and \"aboveNPercent\"; skipping.");
        return null;
      }
      final double aboveNPercent = aboveNPercentRaw.toDouble();
      return InvitationMatch.either(
        namePattern: namePattern,
        topN: topN,
        aboveNPercent: aboveNPercent,
        additionalPatterns: additionalPatterns,
        negativePatterns: negativePatterns,
        afterDate: afterDate,
        minimumCompetitors: minimumCompetitors,
        priority: priority,
      );
    }
    else if(type == "both") {
      final int? topN = raw["topN"] as int?;
      final num? aboveNPercentRaw = raw["aboveNPercent"] as num?;
      if(topN == null || aboveNPercentRaw == null) {
        console.print("both invitationMatches entry must define both \"topN\" and \"aboveNPercent\"; skipping.");
        return null;
      }
      final double aboveNPercent = aboveNPercentRaw.toDouble();
      return InvitationMatch.both(
        namePattern: namePattern,
        topN: topN,
        aboveNPercent: aboveNPercent,
        additionalPatterns: additionalPatterns,
        negativePatterns: negativePatterns,
        afterDate: afterDate,
        minimumCompetitors: minimumCompetitors,
        priority: priority,
      );
    }
    else {
      console.print("Unsupported invitationMatches type \"${type}\"; skipping.");
      return null;
    }
  }

  /// Get invitations for a given group.
  ///
  /// Returns the number of invitations added.
  int getRatingInvitations({
    required RatingSystem ratingSystem,
    required List<DbShooterRating> ratings,
    required RatingGroup group,
    /// Whether this is a run over lady ratings for reserved lady slots.
    required bool lady,
    required Console console,
    required DateTime? activeSince,
    required int neededSlots,
    required Map<RatingGroup, int> filledSlotsByGroup,
    required Map<String, Invitation> invitationsByMemberNumber,
    required List<Invitation> invitations,
    required Map<RatingGroup, List<Invitation>> invitationsByGroup,
    required Map<RatingGroup, List<Invitation>> ladyInvitationsByGroup,
    required bool multipleDivisionRatingQualification,
  }) {
    var ratingsList = [...ratings];
    ratingsList.retainWhere((r) {
      final dateInRange = activeSince == null || r.lastSeen.isAfter(activeSince);
      final ladyMatches = !lady || r.female;
      return dateInRange && ladyMatches;
    });
    ratingsList.sort((a, b) => b.rating.compareTo(a.rating));

    int invitationsAdded = 0;
    for(var rating in ratingsList) {
      bool foundExistingInvitation = false;
      for(var number in rating.allPossibleMemberNumbers) {
        final existingInvitation = invitationsByMemberNumber[number];
        if(existingInvitation != null) {
          foundExistingInvitation = true;

          if(multipleDivisionRatingQualification) {
            existingInvitation.groups.addIfMissing(group);
            existingInvitation.earnedByRatings.addIfMissing(group);
          }
          break;
        }
      }
      if(foundExistingInvitation) {
        continue;
      }

      var invitation = Invitation(groups: [group], rating: ratingSystem.wrapDbRating(rating), fallbackSlot: false, reservedSlot: lady);
      invitation.earnedByRatings.add(group);
      invitations.add(invitation);
      invitationsByGroup.addToList(group, invitation);
      filledSlotsByGroup.increment(group);

      // Regardless of whether we're doing reserved lady slots, record lady invitations.
      if(rating.female) {
        ladyInvitationsByGroup.addToList(group, invitation);
      }
      invitationsAdded += 1;
      for(var number in rating.allPossibleMemberNumbers) {
        invitationsByMemberNumber[number] = invitation;
      }

      if(invitationsAdded >= neededSlots) {
        break;
      }
    }
    return invitationsAdded;
  }

  Future<int> getMatchInvitations({
    required List<InvitationMatch> matchesAtPriority,
    required MatchPointer pointer,
    required AnalystDatabase db,
    required DbRatingProject project,
    required RatingSystem ratingSystem,
    required Map<RatingGroup, int> maximumSlotsByGroup,
    required Map<RatingGroup, int> filledSlotsByGroup,
    required List<_ExcludedGroupsRule> excludedGroupsRules,
    required List<RatingGroup> groups,
    /// Whether to handle reserved lady slots.
    required bool ladySlots,
    /// Whether to score ladies only.
    required bool lady,
    required Console console,
    required Map<String, Invitation> invitationsByMemberNumber,
    required List<Invitation> invitations,
    required Map<RatingGroup, List<Invitation>> invitationsByGroup,
    required Map<RatingGroup, List<Invitation>> ladyInvitationsByGroup,
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
      // console.print("Processing match: ${match.name}");
      for(var group in groups) {
        // If this match name is configured to exclude this group, skip it.
        bool isExcludedForGroup = false;
        for(final rule in excludedGroupsRules) {
          if(rule.matchesName(match.name) && rule.groups.contains(group)) {
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

        var relativeMatchScores = invitationMatch.getRelativeMatchScores(match, group, lady: lady);
        if(relativeMatchScores.isNotEmpty) {
          for(var relativeMatchScore in relativeMatchScores) {
            var rating = db.maybeKnownShooterSync(project: project, group: group, memberNumber: relativeMatchScore.shooter.memberNumber);
            if(rating == null) {
              continue;
            }

            bool foundExistingInvitation = false;
            for(var number in rating.allPossibleMemberNumbers) {
              final existingInvitation = invitationsByMemberNumber[number];
              if(existingInvitation != null) {
                // Don't add to invitationsByGroup for the new group to avoid double-including
                // competitors.
                existingInvitation.groups.addIfMissing(group);
                existingInvitation.relativeMatchScores.add(relativeMatchScore);
                existingInvitation.earnedAtMatches.add(match);
                existingInvitation.matchCriteria.add(invitationMatch);
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
              matchCriteria: [invitationMatch],
              fallbackSlot: false, // fallback slots handled in a later pass
              reservedSlot: ladySlots && lady,
            );
            invitations.add(invitation);
            invitationsByGroup.addToList(group, invitation);
            if(rating.female) {
              ladyInvitationsByGroup.addToList(group, invitation);
            }
            invitationsFromMatch++;
            filledSlotsByGroup.increment(group);
            for(var number in rating.allPossibleMemberNumbers) {
              invitationsByMemberNumber[number] = invitation;
            }
          }
        }
      }
    }
    if(invitationsFromMatch > 0) {
      // console.print("${pointer.name} - $invitationsFromMatch ${lady ? "lady" : "general"} invitations");
    }
    return invitationsFromMatch;
  }
}

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
    this.relativeMatchScores = const [],
    this.earnedAtMatches = const [],
    this.matchCriteria = const [],
    required this.fallbackSlot,
    required this.reservedSlot,
  });

  Map<String, dynamic> toJson() {
    return {
      "memberNumber": rating.memberNumber,
      "name": rating.name,
      "email": rating.email ?? "",
      "groups": groups.map((g) => g.name).toList(),
      "rating": double.tryParse(rating.formattedRating()) ?? 0,
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

class InvitationMatch {
  RegExp namePattern;
  List<RegExp> additionalPatterns = [];
  List<RegExp> negativePatterns = [];
  DateTime? afterDate;
  int? topN;
  double? aboveNPercent;
  bool either;
  bool both;
  int minimumCompetitors = 0;
  int priority = 1;

  InvitationMatch.topN({
    required this.namePattern,
    this.additionalPatterns = const [],
    this.negativePatterns = const [],
    this.afterDate,
    required this.topN,
    this.minimumCompetitors = 0,
    this.either = false,
    this.both = false,
    this.priority = 1,
  }) : aboveNPercent = null;

  InvitationMatch.aboveNPercent({
    required this.namePattern,
    this.additionalPatterns = const [],
    this.negativePatterns = const [],
    this.afterDate,
    required this.aboveNPercent,
    this.minimumCompetitors = 0,
    this.either = false,
    this.both = false,
    this.priority = 1,
  }) : topN = null;

  InvitationMatch.either({
    required this.namePattern,
    required this.topN,
    required this.aboveNPercent,
    this.additionalPatterns = const [],
    this.negativePatterns = const [],
    this.afterDate,
    this.either = true,
    this.minimumCompetitors = 0,
    this.both = false,
    this.priority = 1,
  });

  InvitationMatch.both({
    required this.namePattern,
    required this.topN,
    required this.aboveNPercent,
    this.additionalPatterns = const [],
    this.negativePatterns = const [],
    this.afterDate,
    this.either = false,
    this.both = true,
    this.minimumCompetitors = 0,
    this.priority = 1,
  });

  bool pointerEligible(MatchPointer pointer) {
    if(afterDate != null && pointer.date!.isBefore(afterDate!)) {
      return false;
    }

    bool matchesAllPatterns = true;

    if(!namePattern.hasMatch(pointer.name)) {
      matchesAllPatterns = false;
    }

    for(var pattern in additionalPatterns) {
      if(!pattern.hasMatch(pointer.name)) {
        matchesAllPatterns = false;
        break;
      }
    }

    if(!matchesAllPatterns) {
      return false;
    }

    bool matchesAnyNegativePatterns = false;
    for(var pattern in negativePatterns) {
      if(pattern.hasMatch(pointer.name)) {
        matchesAnyNegativePatterns = true;
        break;
      }
    }

    return !matchesAnyNegativePatterns && matchesAllPatterns;
  }

  bool matchEligible(ShootingMatch match) {
    if(afterDate != null && match.date.isBefore(afterDate!)) {
      return false;
    }

    bool matchesAllPatterns = true;
    if(!namePattern.hasMatch(match.name)) {
      matchesAllPatterns = false;
    }

    for(var pattern in additionalPatterns) {
      if(!pattern.hasMatch(match.name)) {
        matchesAllPatterns = false;
        break;
      }
    }

    if(!matchesAllPatterns) {
      return false;
    }

    bool matchesAnyNegativePatterns = false;
    for(var pattern in negativePatterns) {
      if(pattern.hasMatch(match.name)) {
        matchesAnyNegativePatterns = true;
        break;
      }
    }

    return !matchesAnyNegativePatterns && matchesAllPatterns;
  }

  List<RelativeMatchScore> getRelativeMatchScores(ShootingMatch match, RatingGroup group, {bool lady = false}) {
    if(!matchEligible(match)) {
      return [];
    }

    var divisions = group.divisions;
    var shooters = match.filterShooters(divisions: divisions, ladyOnly: lady);
    if(shooters.length < minimumCompetitors) {
      return [];
    }

    var scores = match.getScores(shooters: shooters);

    if(either) {
      List<RelativeMatchScore> outScores = [];
      for(var score in scores.values) {
        if(aboveNPercent != null && score.ratio > aboveNPercent!) {
          outScores.add(score);
        }
        else if(topN != null && score.place <= topN!) {
          outScores.add(score);
        }
      }
      return outScores;
    }
    else if(both) {
      List<RelativeMatchScore> outScores = [];
      for(var score in scores.values) {
        bool matchesPercent = score.ratio > aboveNPercent!;
        bool matchesTopN = score.place <= topN!;
        if(matchesPercent && matchesTopN) {
          outScores.add(score);
        }
      }
      return outScores;
    }
    else {
      if(topN != null) {
        return scores.values.take(topN!).toList();
      }
      else if(aboveNPercent != null) {
        return scores.values.where((s) => s.ratio > aboveNPercent!).toList();
      }
      else {
        return scores.values.toList();
      }
    }
  }

  Map<String, dynamic> toJson() {
    String type;
    if(either) {
      type = "either";
    }
    else if(both) {
      type = "both";
    }
    else if(topN != null) {
      type = "topN";
    }
    else if(aboveNPercent != null) {
      type = "aboveNPercent";
    }
    else {
      type = "unknown";
    }
    return {
      "namePattern": namePattern.pattern,
      "afterDate": afterDate != null ? programmerYmdFormat.format(afterDate!) : null,
      "topN": topN,
      "aboveNPercent": aboveNPercent,
      "minimumCompetitors": minimumCompetitors,
      "priority": priority,
      "type": type,
    };
  }
}

class _ExcludedGroupsRule {
  final List<RegExp> namePatterns;
  final List<RatingGroup> groups;

  _ExcludedGroupsRule({
    required this.namePatterns,
    required this.groups,
  });

  bool matchesName(String matchName) {
    for(final pattern in namePatterns) {
      if(pattern.hasMatch(matchName)) {
        return true;
      }
    }
    return false;
  }
}