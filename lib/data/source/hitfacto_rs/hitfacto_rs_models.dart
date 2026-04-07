/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:convert';

/// One row from [GET /v1/matches](https://hitfacto.rs/openapi.json).
class HitfactoRsMatchListRow {
  final String matchUuid;
  final String matchName;
  final String? matchDate;
  final String? matchType;
  final String? matchSubtype;

  HitfactoRsMatchListRow({
    required this.matchUuid,
    required this.matchName,
    this.matchDate,
    this.matchType,
    this.matchSubtype,
  });

  factory HitfactoRsMatchListRow.fromJson(Map<String, dynamic> j) {
    return HitfactoRsMatchListRow(
      matchUuid: j["match_uuid"] as String? ?? "",
      matchName: j["match_name"] as String? ?? "",
      matchDate: j["match_date"] as String?,
      matchType: j["match_type"] as String?,
      matchSubtype: j["match_subtype"] as String?,
    );
  }
}

/// Paginated list response for [/v1/matches](https://hitfacto.rs/openapi.json).
class HitfactoRsMatchListPage {
  final List<HitfactoRsMatchListRow> data;
  final String? nextCursor;
  final bool hasMore;

  HitfactoRsMatchListPage({
    required this.data,
    this.nextCursor,
    required this.hasMore,
  });

  factory HitfactoRsMatchListPage.fromJson(Map<String, dynamic> j) {
    final raw = j["data"];
    final list = <HitfactoRsMatchListRow>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map<String, dynamic>) {
          list.add(HitfactoRsMatchListRow.fromJson(e));
        }
      }
    }
    return HitfactoRsMatchListPage(
      data: list,
      nextCursor: j["next_cursor"] as String?,
      hasMore: j["has_more"] as bool? ?? false,
    );
  }
}

/// Stage summary from [GET /v1/matches/{uuid}](https://hitfacto.rs/openapi.json).
class HitfactoRsStageSummary {
  final int id;
  final int stageNumber;
  final String stageName;
  final String scoringType;
  final bool isClassifier;
  final String? classifierCode;
  final int totalPoints;
  final int numTargets;

  HitfactoRsStageSummary({
    required this.id,
    required this.stageNumber,
    required this.stageName,
    required this.scoringType,
    required this.isClassifier,
    this.classifierCode,
    required this.totalPoints,
    required this.numTargets,
  });

  factory HitfactoRsStageSummary.fromJson(Map<String, dynamic> j) {
    return HitfactoRsStageSummary(
      id: (j["id"] as num?)?.toInt() ?? 0,
      stageNumber: (j["stage_number"] as num?)?.toInt() ?? 0,
      stageName: j["stage_name"] as String? ?? "",
      scoringType: j["scoring_type"] as String? ?? "Comstock",
      isClassifier: j["is_classifier"] as bool? ?? false,
      classifierCode: j["classifier_code"] as String?,
      totalPoints: (j["total_points"] as num?)?.toInt() ?? 0,
      numTargets: (j["num_targets"] as num?)?.toInt() ?? 0,
    );
  }
}

/// Full match detail from [GET /v1/matches/{uuid}](https://hitfacto.rs/openapi.json).
class HitfactoRsMatchDetail {
  final String matchUuid;
  final String matchName;
  final String? matchDate;
  final String? matchType;
  final String? matchSubtype;
  final String? matchLevel;
  final List<HitfactoRsStageSummary> stages;

  HitfactoRsMatchDetail({
    required this.matchUuid,
    required this.matchName,
    this.matchDate,
    this.matchType,
    this.matchSubtype,
    this.matchLevel,
    required this.stages,
  });

  factory HitfactoRsMatchDetail.fromJson(Map<String, dynamic> j) {
    final stagesRaw = j["stages"];
    final stages = <HitfactoRsStageSummary>[];
    if (stagesRaw is List) {
      for (final e in stagesRaw) {
        if (e is Map<String, dynamic>) {
          stages.add(HitfactoRsStageSummary.fromJson(e));
        }
      }
    }
    return HitfactoRsMatchDetail(
      matchUuid: j["match_uuid"] as String? ?? "",
      matchName: j["match_name"] as String? ?? "",
      matchDate: j["match_date"] as String?,
      matchType: j["match_type"] as String?,
      matchSubtype: j["match_subtype"] as String?,
      matchLevel: j["match_level"] as String?,
      stages: stages,
    );
  }
}

/// One score line from [GET /v1/matches/{uuid}/results](https://hitfacto.rs/openapi.json).
class HitfactoRsResultRow {
  final int identityId;
  final String firstName;
  final String lastName;
  final String memberNumber;
  final String division;
  final String powerFactor;
  final String classification;
  final int stageNumber;
  final String stageName;
  final int rawPoints;
  final double timeSeconds;
  final List<double> stringTimes;
  final List<List<double>> splitTimes;
  final double hitFactor;
  final int alphas;
  final int bravos;
  final int charlies;
  final int deltas;
  final int misses;
  final int noShoots;
  final int procedurals;
  final bool dnf;
  final bool stageDq;

  HitfactoRsResultRow({
    required this.identityId,
    required this.firstName,
    required this.lastName,
    required this.memberNumber,
    required this.division,
    required this.classification,
    required this.powerFactor,
    required this.stageNumber,
    required this.stageName,
    required this.rawPoints,
    required this.timeSeconds,
    required this.stringTimes,
    required this.splitTimes,
    required this.hitFactor,
    required this.alphas,
    required this.bravos,
    required this.charlies,
    required this.deltas,
    required this.misses,
    required this.noShoots,
    required this.procedurals,
    required this.dnf,
    required this.stageDq,
  });

  factory HitfactoRsResultRow.fromJson(Map<String, dynamic> j) {
    final encodedJsonSplits = j["shot_splits"] as String?;
    final stringSplits = <List<double>>[];
    if(encodedJsonSplits != null) {
      final decodedSplits = jsonDecode(encodedJsonSplits);
      if(decodedSplits is List<dynamic>) {
        for(final d in decodedSplits) {
          if(d is Map<String, dynamic>) {
            var times = (d["times"] as List<dynamic>?)?.map((e) => (e as num?)?.toDouble() ?? 0.0).toList() ?? [];
            stringSplits.add(times);
          }
        }
      }
    }

    return HitfactoRsResultRow(
      identityId: (j["identity_id"] as num?)?.toInt() ?? 0,
      firstName: j["first_name"] as String? ?? "",
      lastName: j["last_name"] as String? ?? "",
      memberNumber: j["member_number"] as String? ?? "",
      division: j["division"] as String? ?? "",
      classification: j["classification"] as String? ?? "",
      powerFactor: j["power_factor"] as String? ?? "",
      stageNumber: (j["stage_number"] as num?)?.toInt() ?? 0,
      stageName: j["stage_name"] as String? ?? "",
      rawPoints: (j["raw_points"] as num?)?.toInt() ?? 0,
      timeSeconds: (j["time_seconds"] as num?)?.toDouble() ?? 0.0,
      stringTimes: (j["string_times"] as List<dynamic>?)?.map((e) => (e as num?)?.toDouble() ?? 0.0).toList() ?? [],
      splitTimes: stringSplits,
      hitFactor: (j["hit_factor"] as num?)?.toDouble() ?? 0.0,
      alphas: ((j["alphas"] as num?)?.toInt() ?? 0) +
        ((j["popper_hits"] as num?)?.toInt() ?? 0),
      bravos: (j["bravos"] as num?)?.toInt() ?? 0,
      charlies: (j["charlies"] as num?)?.toInt() ?? 0,
      deltas: (j["deltas"] as num?)?.toInt() ?? 0,
      misses:
        ((j["misses"] as num?)?.toInt() ?? 0) +
        ((j["popper_misses"] as num?)?.toInt() ?? 0),
      noShoots: (j["no_shoots"] as num?)?.toInt() ?? 0 +
        ((j["popper_no_shoots"] as num?)?.toInt() ?? 0),
      procedurals: (j["procedurals"] as num?)?.toInt() ?? 0,
      dnf: j["dnf"] as bool? ?? false,
      stageDq: j["stage_dq"] as bool? ?? false,
    );
  }
}

class HitfactoRsResultsPage {
  final List<HitfactoRsResultRow> data;
  final String? nextCursor;
  final bool hasMore;

  HitfactoRsResultsPage({
    required this.data,
    this.nextCursor,
    required this.hasMore,
  });

  factory HitfactoRsResultsPage.fromJson(Map<String, dynamic> j) {
    final raw = j["data"];
    final list = <HitfactoRsResultRow>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map<String, dynamic>) {
          list.add(HitfactoRsResultRow.fromJson(e));
        }
      }
    }
    return HitfactoRsResultsPage(
      data: list,
      nextCursor: j["next_cursor"] as String?,
      hasMore: j["has_more"] as bool? ?? false,
    );
  }
}
