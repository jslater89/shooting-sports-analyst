/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "package:shooting_sports_analyst/data/database/schema/ratings.dart";
import "package:shooting_sports_analyst/data/sport/model.dart";
import "package:shooting_sports_analyst/util.dart";

enum InvitationMatchType {
  topN,
  aboveNPercent,
  either,
  both;

  String get label => switch(this) {
    topN => "Top N",
    aboveNPercent => "Above N%",
    either => "Either",
    both => "Both",
  };

  String get tomlValue => switch(this) {
    topN => "topN",
    aboveNPercent => "aboveNPercent",
    either => "either",
    both => "both",
  };

  static InvitationMatchType? fromToml(String? value) {
    if(value == null || value == "topN") {
      return topN;
    }
    else if(value == "aboveNPercent") {
      return aboveNPercent;
    }
    else if(value == "either") {
      return either;
    }
    else if(value == "both") {
      return both;
    }
    return null;
  }
}

/// Which invite-engine pass(es) a finish-order rule runs on.
enum InvitationMatchScope {
  general,
  lady,
  junior,
  senior,
  /// Every enabled reserved pass (lady / junior / senior), not the overall pass.
  categories,
  all;

  String get label => switch(this) {
    general => "General",
    lady => "Lady",
    junior => "Junior",
    senior => "Senior",
    categories => "Categories",
    all => "All",
  };

  String get tomlValue => switch(this) {
    general => "general",
    lady => "lady",
    junior => "junior",
    senior => "senior",
    categories => "categories",
    all => "all",
  };

  /// Missing/empty → [all] for backward compatibility. Unknown → [all] with warning.
  static InvitationMatchScope fromToml(String? value, List<String> warnings) {
    if(value == null || value.isEmpty) {
      return all;
    }
    for(final scope in InvitationMatchScope.values) {
      if(scope.tomlValue == value) {
        return scope;
      }
    }
    warnings.add("Unknown invitationMatches scope \"$value\"; using all.");
    return all;
  }

  bool get appliesToGeneralPass => this == general || this == all;

  bool appliesToReservedPass(InvitationMatchPassKind kind) {
    return switch(kind) {
      InvitationMatchPassKind.general => appliesToGeneralPass,
      InvitationMatchPassKind.lady => this == lady || this == categories || this == all,
      InvitationMatchPassKind.junior => this == junior || this == categories || this == all,
      InvitationMatchPassKind.senior => this == senior || this == categories || this == all,
      InvitationMatchPassKind.combinedAge =>
        this == junior || this == senior || this == categories || this == all,
    };
  }
}

/// Engine pass kind used for scope filtering.
enum InvitationMatchPassKind {
  general,
  lady,
  junior,
  senior,
  combinedAge,
}

/// A finish-order rule that awards invitational slots from matching matches.
class InvitationMatch {
  /// Optional short label for crowded configs.
  String? name;
  InvitationMatchScope scope;
  RegExp? namePattern;
  List<String> sourceIds;
  List<RegExp> additionalPatterns;
  List<RegExp> negativePatterns;
  DateTime? afterDate;
  int? topN;
  double? aboveNPercent;
  bool either;
  bool both;
  int minimumCompetitors;
  int priority;

  InvitationMatch.topN({
    this.name,
    this.scope = InvitationMatchScope.all,
    this.namePattern,
    List<String>? sourceIds,
    List<RegExp>? additionalPatterns,
    List<RegExp>? negativePatterns,
    this.afterDate,
    required this.topN,
    this.minimumCompetitors = 0,
    this.either = false,
    this.both = false,
    this.priority = 1,
  }) : sourceIds = sourceIds ?? [],
       additionalPatterns = additionalPatterns ?? [],
       negativePatterns = negativePatterns ?? [],
       aboveNPercent = null;

  InvitationMatch.aboveNPercent({
    this.name,
    this.scope = InvitationMatchScope.all,
    this.namePattern,
    List<String>? sourceIds,
    List<RegExp>? additionalPatterns,
    List<RegExp>? negativePatterns,
    this.afterDate,
    required this.aboveNPercent,
    this.minimumCompetitors = 0,
    this.either = false,
    this.both = false,
    this.priority = 1,
  }) : sourceIds = sourceIds ?? [],
       additionalPatterns = additionalPatterns ?? [],
       negativePatterns = negativePatterns ?? [],
       topN = null;

  InvitationMatch.either({
    this.name,
    this.scope = InvitationMatchScope.all,
    this.namePattern,
    List<String>? sourceIds,
    required this.topN,
    required this.aboveNPercent,
    List<RegExp>? additionalPatterns,
    List<RegExp>? negativePatterns,
    this.afterDate,
    this.either = true,
    this.minimumCompetitors = 0,
    this.both = false,
    this.priority = 1,
  }) : sourceIds = sourceIds ?? [],
       additionalPatterns = additionalPatterns ?? [],
       negativePatterns = negativePatterns ?? [];

  InvitationMatch.both({
    this.name,
    this.scope = InvitationMatchScope.all,
    this.namePattern,
    List<String>? sourceIds,
    required this.topN,
    required this.aboveNPercent,
    List<RegExp>? additionalPatterns,
    List<RegExp>? negativePatterns,
    this.afterDate,
    this.either = false,
    this.both = true,
    this.minimumCompetitors = 0,
    this.priority = 1,
  }) : sourceIds = sourceIds ?? [],
       additionalPatterns = additionalPatterns ?? [],
       negativePatterns = negativePatterns ?? [];

  InvitationMatchType get type {
    if(either) {
      return InvitationMatchType.either;
    }
    else if(both) {
      return InvitationMatchType.both;
    }
    else if(topN != null) {
      return InvitationMatchType.topN;
    }
    else {
      return InvitationMatchType.aboveNPercent;
    }
  }

  String get ruleSummary {
    final String base;
    switch(type) {
      case InvitationMatchType.topN:
        base = "Top ${topN ?? "?"}";
      case InvitationMatchType.aboveNPercent:
        base = "Above ${((aboveNPercent ?? 0) * 100).toStringAsFixed(0)}%";
      case InvitationMatchType.either:
        base = "Top ${topN ?? "?"} or above ${((aboveNPercent ?? 0) * 100).toStringAsFixed(0)}%";
      case InvitationMatchType.both:
        base = "Top ${topN ?? "?"} and above ${((aboveNPercent ?? 0) * 100).toStringAsFixed(0)}%";
    }
    if(scope == InvitationMatchScope.all) {
      return base;
    }
    return "$base (${scope.label.toLowerCase()})";
  }

  /// Prefer [name] when set; otherwise [ruleSummary].
  String get displayLabel {
    final trimmed = name?.trim();
    if(trimmed != null && trimmed.isNotEmpty) {
      return trimmed;
    }
    return ruleSummary;
  }

  List<RegExp> get includePatterns => [
    if(namePattern != null) namePattern!,
    ...additionalPatterns,
  ];

  /// True if this rule can identify matches (source IDs and/or include name patterns).
  bool get hasIdentification => sourceIds.isNotEmpty || includePatterns.isNotEmpty;

  InvitationMatch copy() {
    return _copyWithType(type);
  }

  InvitationMatch withType(InvitationMatchType newType) {
    return _copyWithType(newType);
  }

  InvitationMatch _copyWithType(InvitationMatchType newType) {
    switch(newType) {
      case InvitationMatchType.topN:
        return InvitationMatch.topN(
          name: name,
          scope: scope,
          namePattern: namePattern,
          sourceIds: [...sourceIds],
          additionalPatterns: [...additionalPatterns],
          negativePatterns: [...negativePatterns],
          afterDate: afterDate,
          topN: topN ?? 1,
          minimumCompetitors: minimumCompetitors,
          priority: priority,
        );
      case InvitationMatchType.aboveNPercent:
        return InvitationMatch.aboveNPercent(
          name: name,
          scope: scope,
          namePattern: namePattern,
          sourceIds: [...sourceIds],
          additionalPatterns: [...additionalPatterns],
          negativePatterns: [...negativePatterns],
          afterDate: afterDate,
          aboveNPercent: aboveNPercent ?? 0.9,
          minimumCompetitors: minimumCompetitors,
          priority: priority,
        );
      case InvitationMatchType.either:
        return InvitationMatch.either(
          name: name,
          scope: scope,
          namePattern: namePattern,
          sourceIds: [...sourceIds],
          additionalPatterns: [...additionalPatterns],
          negativePatterns: [...negativePatterns],
          afterDate: afterDate,
          topN: topN ?? 1,
          aboveNPercent: aboveNPercent ?? 0.9,
          minimumCompetitors: minimumCompetitors,
          priority: priority,
        );
      case InvitationMatchType.both:
        return InvitationMatch.both(
          name: name,
          scope: scope,
          namePattern: namePattern,
          sourceIds: [...sourceIds],
          additionalPatterns: [...additionalPatterns],
          negativePatterns: [...negativePatterns],
          afterDate: afterDate,
          topN: topN ?? 1,
          aboveNPercent: aboveNPercent ?? 0.9,
          minimumCompetitors: minimumCompetitors,
          priority: priority,
        );
    }
  }

  bool pointerEligible(MatchPointer pointer) {
    if(afterDate != null && (pointer.date == null || pointer.date!.isBefore(afterDate!))) {
      return false;
    }
    return _matchesIdentification(
      name: pointer.name,
      sourceIds: pointer.sourceIds,
    );
  }

  bool matchEligible(ShootingMatch match) {
    if(afterDate != null && match.date.isBefore(afterDate!)) {
      return false;
    }
    return _matchesIdentification(
      name: match.name,
      sourceIds: match.sourceIds,
    );
  }

  /// Identification is AND of whatever is specified: source IDs if present,
  /// all include name patterns if present, then negative patterns exclude.
  bool _matchesIdentification({required String name, required List<String> sourceIds}) {
    if(!hasIdentification) {
      return false;
    }

    if(this.sourceIds.isNotEmpty) {
      final overlap = sourceIds.any((id) => this.sourceIds.contains(id));
      if(!overlap) {
        return false;
      }
    }

    final patterns = includePatterns;
    if(patterns.isNotEmpty) {
      for(var pattern in patterns) {
        if(!pattern.hasMatch(name)) {
          return false;
        }
      }
    }

    for(var pattern in negativePatterns) {
      if(pattern.hasMatch(name)) {
        return false;
      }
    }

    return true;
  }

  List<RelativeMatchScore> getRelativeMatchScores(
    ShootingMatch match,
    {
      required List<Division> divisions,
      bool lady = false,
      List<AgeCategory>? ageCategories,
  }) {
    if(!matchEligible(match)) {
      return [];
    }

    if(ageCategories != null && ageCategories.isEmpty) {
      return [];
    }

    var shooters = match.filterShooters(
      divisions: divisions,
      ladyOnly: lady,
      ageCategories: ageCategories,
    );
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
    final map = <String, dynamic>{
      "type": type.tomlValue,
      "scope": scope.tomlValue,
      "sourceIds": [...sourceIds],
      "additionalPatterns": additionalPatterns.map((p) => p.pattern).toList(),
      "negativePatterns": negativePatterns.map((p) => p.pattern).toList(),
      "minimumCompetitors": minimumCompetitors,
      "priority": priority,
    };
    final trimmedName = name?.trim();
    if(trimmedName != null && trimmedName.isNotEmpty) {
      map["name"] = trimmedName;
    }
    if(namePattern != null) {
      map["namePattern"] = namePattern!.pattern;
    }
    if(afterDate != null) {
      map["afterDate"] = programmerYmdFormat.format(afterDate!);
    }
    if(topN != null) {
      map["topN"] = topN;
    }
    if(aboveNPercent != null) {
      map["aboveNPercent"] = aboveNPercent;
    }
    return map;
  }
}

/// Skip specific rating groups for matches identified by name patterns and/or source IDs.
class ExcludedGroupsRule {
  List<RegExp> namePatterns;
  List<String> sourceIds;
  List<String> groupKeys;

  ExcludedGroupsRule({
    List<RegExp>? namePatterns,
    List<String>? sourceIds,
    List<String>? groupKeys,
  }) : namePatterns = namePatterns ?? [],
       sourceIds = sourceIds ?? [],
       groupKeys = groupKeys ?? [];

  bool get hasIdentification => sourceIds.isNotEmpty || namePatterns.isNotEmpty;

  ExcludedGroupsRule copy() {
    return ExcludedGroupsRule(
      namePatterns: [...namePatterns],
      sourceIds: [...sourceIds],
      groupKeys: [...groupKeys],
    );
  }

  /// True if this rule applies to the given match.
  ///
  /// Source IDs and name patterns are AND of whatever is specified.
  /// Name patterns themselves are OR (any pattern matches).
  bool matches({required String name, required List<String> sourceIds}) {
    if(!hasIdentification) {
      return false;
    }

    if(this.sourceIds.isNotEmpty) {
      final overlap = sourceIds.any((id) => this.sourceIds.contains(id));
      if(!overlap) {
        return false;
      }
    }

    if(namePatterns.isNotEmpty) {
      bool anyName = false;
      for(final pattern in namePatterns) {
        if(pattern.hasMatch(name)) {
          anyName = true;
          break;
        }
      }
      if(!anyName) {
        return false;
      }
    }

    return true;
  }

  Map<String, dynamic> toJson() {
    return {
      "namePatterns": namePatterns.map((p) => p.pattern).toList(),
      "sourceIds": [...sourceIds],
      "groups": [...groupKeys],
    };
  }
}
