/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "package:collection/collection.dart";
import "package:shooting_sports_analyst/data/database/schema/ratings.dart";
import "package:shooting_sports_analyst/data/ranking/invitational/invitation_match.dart";
import "package:shooting_sports_analyst/util.dart";
import "package:toml/toml.dart";

/// Unresolved invitational-invite configuration.
///
/// Group keys are stored as strings (uuid preferred; name/uuid-contains
/// fallback at generate time). Match identification uses source IDs and/or
/// name patterns rather than live [RatingGroup] / [MatchPointer] links.
class InvitationalInviteConfig {
  String? projectName;
  List<String> groupKeys;
  Map<String, int> slotsByGroup;
  bool ladySlots;
  Map<String, int> reservedLadySlotsByGroup;
  bool juniorSlots;
  bool seniorSlots;
  bool combineJuniorSeniorSlots;
  Map<String, int> reservedJuniorSlotsByGroup;
  Map<String, int> reservedSeniorSlotsByGroup;
  Map<String, int> reservedJuniorSeniorSlotsByGroup;
  bool multipleDivisionRatingQualification;
  bool combinedScoringForMultiDivisionGroups;
  bool includeEmails;
  double takeRate;
  DateTime? activeSince;
  List<ExcludedGroupsRule> excludedGroups;
  List<InvitationMatch> invitationMatches;

  InvitationalInviteConfig({
    this.projectName,
    List<String>? groupKeys,
    Map<String, int>? slotsByGroup,
    this.ladySlots = false,
    Map<String, int>? reservedLadySlotsByGroup,
    this.juniorSlots = false,
    this.seniorSlots = false,
    this.combineJuniorSeniorSlots = false,
    Map<String, int>? reservedJuniorSlotsByGroup,
    Map<String, int>? reservedSeniorSlotsByGroup,
    Map<String, int>? reservedJuniorSeniorSlotsByGroup,
    this.multipleDivisionRatingQualification = false,
    this.combinedScoringForMultiDivisionGroups = false,
    this.includeEmails = false,
    this.takeRate = 0.6,
    this.activeSince,
    List<ExcludedGroupsRule>? excludedGroups,
    List<InvitationMatch>? invitationMatches,
  }) : groupKeys = groupKeys ?? [],
       slotsByGroup = slotsByGroup ?? {},
       reservedLadySlotsByGroup = reservedLadySlotsByGroup ?? {},
       reservedJuniorSlotsByGroup = reservedJuniorSlotsByGroup ?? {},
       reservedSeniorSlotsByGroup = reservedSeniorSlotsByGroup ?? {},
       reservedJuniorSeniorSlotsByGroup = reservedJuniorSeniorSlotsByGroup ?? {},
       excludedGroups = excludedGroups ?? [],
       invitationMatches = invitationMatches ?? [];

  InvitationalInviteConfig copy() {
    return InvitationalInviteConfig(
      projectName: projectName,
      groupKeys: [...groupKeys],
      slotsByGroup: {...slotsByGroup},
      ladySlots: ladySlots,
      reservedLadySlotsByGroup: {...reservedLadySlotsByGroup},
      juniorSlots: juniorSlots,
      seniorSlots: seniorSlots,
      combineJuniorSeniorSlots: combineJuniorSeniorSlots,
      reservedJuniorSlotsByGroup: {...reservedJuniorSlotsByGroup},
      reservedSeniorSlotsByGroup: {...reservedSeniorSlotsByGroup},
      reservedJuniorSeniorSlotsByGroup: {...reservedJuniorSeniorSlotsByGroup},
      multipleDivisionRatingQualification: multipleDivisionRatingQualification,
      includeEmails: includeEmails,
      takeRate: takeRate,
      activeSince: activeSince,
      excludedGroups: excludedGroups.map((e) => e.copy()).toList(),
      invitationMatches: invitationMatches.map((e) => e.copy()).toList(),
    );
  }

  static Result<InvitationalInviteConfigParseResult, StringError> parseToml(String toml) {
    TomlDocument doc;
    try {
      doc = TomlDocument.parse(toml);
    }
    catch(e) {
      return Result.err(StringError("Failed to parse TOML: $e"));
    }
    return fromMap(doc.toMap());
  }

  static Result<InvitationalInviteConfigParseResult, StringError> fromJson(Map<String, dynamic> json) {
    return fromMap(json);
  }

  static Result<InvitationalInviteConfigParseResult, StringError> fromMap(Map<dynamic, dynamic> raw) {
    final warnings = <String>[];
    final config = InvitationalInviteConfig();

    config.projectName = raw["projectName"] as String?;
    config.ladySlots = (raw["ladySlots"] as bool?) ?? false;
    config.juniorSlots = (raw["juniorSlots"] as bool?) ?? false;
    config.seniorSlots = (raw["seniorSlots"] as bool?) ?? false;
    config.combineJuniorSeniorSlots = (raw["combineJuniorSeniorSlots"] as bool?) ?? false;
    config.multipleDivisionRatingQualification = (raw["multipleDivisionRatingQualification"] as bool?) ?? false;
    config.combinedScoringForMultiDivisionGroups = (raw["combinedScoringForMultiDivisionGroups"] as bool?) ?? false;
    config.includeEmails = (raw["includeEmails"] as bool?) ?? false;
    config.takeRate = (raw["takeRate"] as num?)?.toDouble() ?? 0.6;

    final String? activeSinceStr = raw["activeSince"] as String?;
    if(activeSinceStr != null) {
      try {
        config.activeSince = DateTime.parse(activeSinceStr);
      }
      catch(_) {
        warnings.add("Could not parse activeSince \"$activeSinceStr\"; ignoring.");
      }
    }

    final List<dynamic>? configGroupKeys = raw["groups"] as List<dynamic>?;
    if(configGroupKeys != null) {
      for(final dynamic keyDynamic in configGroupKeys) {
        if(keyDynamic is String) {
          config.groupKeys.add(keyDynamic);
        }
        else {
          warnings.add("Group keys must be strings. Got: ${keyDynamic.runtimeType}");
        }
      }
    }

    config.slotsByGroup = _intMapFrom(raw["slotsByGroup"], "slotsByGroup", warnings);
    config.reservedLadySlotsByGroup = _intMapFrom(raw["reservedLadySlotsByGroup"], "reservedLadySlotsByGroup", warnings);
    config.reservedJuniorSlotsByGroup = _intMapFrom(raw["reservedJuniorSlotsByGroup"], "reservedJuniorSlotsByGroup", warnings);
    config.reservedSeniorSlotsByGroup = _intMapFrom(raw["reservedSeniorSlotsByGroup"], "reservedSeniorSlotsByGroup", warnings);
    config.reservedJuniorSeniorSlotsByGroup = _intMapFrom(raw["reservedJuniorSeniorSlotsByGroup"], "reservedJuniorSeniorSlotsByGroup", warnings);

    final List<dynamic> rawExcludedGroups = (raw["excludedGroups"] as List<dynamic>?) ?? [];
    for(final dynamic entry in rawExcludedGroups) {
      if(entry is! Map) {
        warnings.add("excludedGroups entries must be tables; got ${entry.runtimeType}");
        continue;
      }
      final parsed = _parseExcludedGroupsRule(entry, warnings);
      if(parsed != null) {
        config.excludedGroups.add(parsed);
      }
    }

    final List<dynamic> rawInvitationMatches = (raw["invitationMatches"] as List<dynamic>?) ?? [];
    for(final dynamic entry in rawInvitationMatches) {
      if(entry is! Map) {
        warnings.add("invitationMatches entries must be tables; got ${entry.runtimeType}");
        continue;
      }
      final parsed = _parseInvitationMatch(entry, warnings);
      if(parsed != null) {
        config.invitationMatches.add(parsed);
      }
    }

    return Result.ok(InvitationalInviteConfigParseResult(
      config: config,
      warnings: warnings,
    ));
  }

  String toToml() {
    final doc = TomlDocument.fromMap(toJson());
    return doc.toString();
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      "ladySlots": ladySlots,
      "juniorSlots": juniorSlots,
      "seniorSlots": seniorSlots,
      "combineJuniorSeniorSlots": combineJuniorSeniorSlots,
      "multipleDivisionRatingQualification": multipleDivisionRatingQualification,
      "combinedScoringForMultiDivisionGroups": combinedScoringForMultiDivisionGroups,
      "includeEmails": includeEmails,
      "takeRate": takeRate,
      "groups": [...groupKeys],
      "slotsByGroup": {
        for(final e in slotsByGroup.entries) e.key: e.value,
      },
      "reservedLadySlotsByGroup": {
        for(final e in reservedLadySlotsByGroup.entries) e.key: e.value,
      },
      "reservedJuniorSlotsByGroup": {
        for(final e in reservedJuniorSlotsByGroup.entries) e.key: e.value,
      },
      "reservedSeniorSlotsByGroup": {
        for(final e in reservedSeniorSlotsByGroup.entries) e.key: e.value,
      },
      "reservedJuniorSeniorSlotsByGroup": {
        for(final e in reservedJuniorSeniorSlotsByGroup.entries) e.key: e.value,
      },
      "excludedGroups": excludedGroups.map((e) => e.toJson()).toList(),
      "invitationMatches": invitationMatches.map((e) => e.toJson()).toList(),
    };
    if(projectName != null && projectName!.isNotEmpty) {
      map["projectName"] = projectName;
    }
    if(activeSince != null) {
      map["activeSince"] = programmerYmdFormat.format(activeSince!);
    }
    return map;
  }

  /// Compare this config against a project's groups and match pointers.
  InvitationalInviteCompatibility checkCompatibility({
    required List<RatingGroup> groups,
    required List<MatchPointer> matchPointers,
  }) {
    final unresolvedGroupKeys = <String>[];
    final unresolvedSourceIds = <String>[];

    final allGroupKeys = <String>{
      ...groupKeys,
      for(final rule in excludedGroups) ...rule.groupKeys,
    };
    for(final key in allGroupKeys) {
      if(findRatingGroup(groups, key) == null) {
        unresolvedGroupKeys.add(key);
      }
    }

    final knownSourceIds = <String>{
      for(final pointer in matchPointers) ...pointer.sourceIds,
    };
    final configSourceIds = <String>{
      for(final rule in excludedGroups) ...rule.sourceIds,
      for(final match in invitationMatches) ...match.sourceIds,
    };
    for(final id in configSourceIds) {
      if(!knownSourceIds.contains(id)) {
        unresolvedSourceIds.add(id);
      }
    }

    return InvitationalInviteCompatibility(
      unresolvedGroupKeys: unresolvedGroupKeys,
      unresolvedSourceIds: unresolvedSourceIds,
    );
  }

  /// True when junior and senior reserved slots share one pool.
  bool get combineAgeSlots => combineJuniorSeniorSlots && juniorSlots && seniorSlots;

  bool get anyReservedSlots => ladySlots || juniorSlots || seniorSlots;
}

class InvitationalInviteConfigParseResult {
  final InvitationalInviteConfig config;
  final List<String> warnings;

  InvitationalInviteConfigParseResult({
    required this.config,
    required this.warnings,
  });
}

class InvitationalInviteCompatibility {
  final List<String> unresolvedGroupKeys;
  final List<String> unresolvedSourceIds;

  InvitationalInviteCompatibility({
    required this.unresolvedGroupKeys,
    required this.unresolvedSourceIds,
  });

  bool get hasIssues => unresolvedGroupKeys.isNotEmpty || unresolvedSourceIds.isNotEmpty;
}

RatingGroup? findRatingGroup(List<RatingGroup> allGroups, String key) {
  return allGroups.firstWhereOrNull((g) =>
    g.uuid == key ||
    g.uuid.contains(key) ||
    g.name.toLowerCase() == key.toLowerCase());
}

Map<String, int> _intMapFrom(dynamic raw, String name, List<String> warnings) {
  final result = <String, int>{};
  if(raw is! Map) {
    return result;
  }
  for(final entry in raw.entries) {
    final key = entry.key.toString();
    final value = entry.value;
    if(value is int) {
      result[key] = value;
    }
    else if(value is num) {
      result[key] = value.round();
    }
    else {
      warnings.add("$name value for \"$key\" must be an integer.");
    }
  }
  return result;
}

List<RegExp> _patternsFromList(dynamic value) {
  if(value is List) {
    return value
        .whereType<String>()
        .map((s) => RegExp(s))
        .toList();
  }
  return [];
}

List<String> _stringsFromList(dynamic value) {
  if(value is List) {
    return value.whereType<String>().toList();
  }
  return [];
}

ExcludedGroupsRule? _parseExcludedGroupsRule(Map<dynamic, dynamic> table, List<String> warnings) {
  final namePatterns = _patternsFromList(table["namePatterns"]);
  final sourceIds = _stringsFromList(table["sourceIds"]);
  if(namePatterns.isEmpty && sourceIds.isEmpty) {
    warnings.add("excludedGroups entry has neither namePatterns nor sourceIds; skipping.");
    return null;
  }

  final groupsDynamic = table["groups"];
  if(groupsDynamic is! List) {
    warnings.add("excludedGroups entry missing \"groups\" list; skipping.");
    return null;
  }
  final groupKeys = groupsDynamic.whereType<String>().toList();
  if(groupKeys.isEmpty) {
    warnings.add("excludedGroups entry has no group keys; skipping.");
    return null;
  }

  return ExcludedGroupsRule(
    namePatterns: namePatterns,
    sourceIds: sourceIds,
    groupKeys: groupKeys,
  );
}

InvitationMatch? _parseInvitationMatch(Map<dynamic, dynamic> raw, List<String> warnings) {
  final String? typeStr = raw["type"] as String?;
  final type = InvitationMatchType.fromToml(typeStr);
  if(type == null) {
    warnings.add("Unsupported invitationMatches type \"$typeStr\"; skipping.");
    return null;
  }

  final String? namePatternStr = raw["namePattern"] as String?;
  final RegExp? namePattern = namePatternStr != null ? RegExp(namePatternStr) : null;
  final sourceIds = _stringsFromList(raw["sourceIds"]);
  final additionalPatterns = _patternsFromList(raw["additionalPatterns"]);
  final negativePatterns = _patternsFromList(raw["negativePatterns"]);

  if(namePattern == null && additionalPatterns.isEmpty && sourceIds.isEmpty) {
    warnings.add("invitationMatches entry has neither namePattern nor sourceIds; skipping.");
    return null;
  }

  DateTime? afterDate;
  final String? afterDateStr = raw["afterDate"] as String?;
  if(afterDateStr != null) {
    try {
      afterDate = DateTime.parse(afterDateStr);
    }
    catch(_) {
      warnings.add("Could not parse afterDate \"$afterDateStr\"; ignoring.");
    }
  }

  final int minimumCompetitors = (raw["minimumCompetitors"] as int?) ?? 0;
  final int priority = (raw["priority"] as int?) ?? 1;

  switch(type) {
    case InvitationMatchType.topN:
      final int? topN = raw["topN"] as int?;
      if(topN == null) {
        warnings.add("topN invitationMatches entry is missing \"topN\"; skipping.");
        return null;
      }
      return InvitationMatch.topN(
        namePattern: namePattern,
        sourceIds: sourceIds,
        additionalPatterns: additionalPatterns,
        negativePatterns: negativePatterns,
        afterDate: afterDate,
        topN: topN,
        minimumCompetitors: minimumCompetitors,
        priority: priority,
      );
    case InvitationMatchType.aboveNPercent:
      final num? aboveNPercentRaw = raw["aboveNPercent"] as num?;
      if(aboveNPercentRaw == null) {
        warnings.add("aboveNPercent invitationMatches entry is missing \"aboveNPercent\"; skipping.");
        return null;
      }
      return InvitationMatch.aboveNPercent(
        namePattern: namePattern,
        sourceIds: sourceIds,
        additionalPatterns: additionalPatterns,
        negativePatterns: negativePatterns,
        afterDate: afterDate,
        aboveNPercent: aboveNPercentRaw.toDouble(),
        minimumCompetitors: minimumCompetitors,
        priority: priority,
      );
    case InvitationMatchType.either:
      final int? topN = raw["topN"] as int?;
      final num? aboveNPercentRaw = raw["aboveNPercent"] as num?;
      if(topN == null || aboveNPercentRaw == null) {
        warnings.add("either invitationMatches entry must define both \"topN\" and \"aboveNPercent\"; skipping.");
        return null;
      }
      return InvitationMatch.either(
        namePattern: namePattern,
        sourceIds: sourceIds,
        topN: topN,
        aboveNPercent: aboveNPercentRaw.toDouble(),
        additionalPatterns: additionalPatterns,
        negativePatterns: negativePatterns,
        afterDate: afterDate,
        minimumCompetitors: minimumCompetitors,
        priority: priority,
      );
    case InvitationMatchType.both:
      final int? topN = raw["topN"] as int?;
      final num? aboveNPercentRaw = raw["aboveNPercent"] as num?;
      if(topN == null || aboveNPercentRaw == null) {
        warnings.add("both invitationMatches entry must define both \"topN\" and \"aboveNPercent\"; skipping.");
        return null;
      }
      return InvitationMatch.both(
        namePattern: namePattern,
        sourceIds: sourceIds,
        topN: topN,
        aboveNPercent: aboveNPercentRaw.toDouble(),
        additionalPatterns: additionalPatterns,
        negativePatterns: negativePatterns,
        afterDate: afterDate,
        minimumCompetitors: minimumCompetitors,
        priority: priority,
      );
  }
}
