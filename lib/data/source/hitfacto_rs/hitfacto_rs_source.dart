/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "package:shooting_sports_analyst/data/source/hitfacto_rs/hitfacto_rs_client.dart";
import "package:shooting_sports_analyst/data/source/hitfacto_rs/hitfacto_rs_code.dart";
import "package:shooting_sports_analyst/data/source/hitfacto_rs/hitfacto_rs_fetch_options.dart";
import "package:shooting_sports_analyst/data/source/hitfacto_rs/hitfacto_rs_match_converter.dart";
import "package:shooting_sports_analyst/data/source/hitfacto_rs/hitfacto_rs_match_type.dart";
import "package:shooting_sports_analyst/data/source/hitfacto_rs/hitfacto_rs_models.dart";
import "package:shooting_sports_analyst/data/source/match_source_error.dart";
import "package:shooting_sports_analyst/data/source/source.dart";
import "package:shooting_sports_analyst/data/sport/match/match.dart";
import "package:shooting_sports_analyst/data/sport/sport.dart";
import "package:shooting_sports_analyst/logger.dart";
import "package:shooting_sports_analyst/util.dart";

final _log = SSALogger("HitfactoRsMatchSource");

class HitfactoRsMatchSource
    extends MatchSource<HitfactoRsMatchType, HitfactoRsMatchFetchOptions> {
  @override
  bool get canSearch => true;

  @override
  String get code => hitfactoRsCode;

  @override
  bool get isImplemented => true;

  @override
  String get name => "Hitfacto.rs";

  @override
  bool get degraded => true;

  @override
  String? get degradedReason => "Hitfacto.rs is not currently publicly available.";

  @override
  List<SportType> get supportedSports => [SportType.uspsa];

  @override
  Future<Result<List<MatchSearchResult<HitfactoRsMatchType>>, MatchSourceError>>
  findMatches(String search) async {
    final page = await HitfactoRsClient.listMatches(query: search, limit: 50);
    if (page.isErr()) {
      return Result.errFrom(page);
    }
    final out = <MatchSearchResult<HitfactoRsMatchType>>[];
    for (final row in page.unwrap().data) {
      if (!_isUspsaMatch(row)) {
        continue;
      }
      DateTime? matchDate;
      if (row.matchDate != null && row.matchDate!.isNotEmpty) {
        try {
          matchDate = programmerYmdFormat.parse(row.matchDate!);
        } catch (e) {
          _log.v("Bad date ${row.matchDate}: $e");
        }
      }
      out.add(
        MatchSearchResult<HitfactoRsMatchType>(
          matchName: row.matchName,
          matchId: row.matchUuid,
          matchSubtype: row.matchSubtype ?? "",
          matchDate: matchDate,
          matchType: HitfactoRsMatchType.uspsaHitFactor,
        ),
      );
    }
    return Result.ok(out);
  }

  bool _isUspsaMatch(HitfactoRsMatchListRow row) {
    final t = row.matchType?.toLowerCase() ?? "";
    final st = row.matchSubtype?.toLowerCase() ?? "";
    return t == "uspsa_p" || st == "uspsa";
  }

  @override
  Future<Result<ShootingMatch, MatchSourceError>> getMatchFromSearch(
    MatchSearchResult<HitfactoRsMatchType> searchResult, {
    SportType? typeHint,
    Sport? sport,
    HitfactoRsMatchFetchOptions? options,
  }) async {
    if (sport != null && sport.type != SportType.uspsa) {
      return Result.err(
        TypeMismatch(attemptedWith: sport.type, detectedType: SportType.uspsa),
      );
    }

    var opts = options ?? const HitfactoRsMatchFetchOptions();
    if (sport != null) {
      opts = opts.copyWith(parseAsSport: sport);
    }

    final uuid = searchResult.matchId;
    final detailResult = await HitfactoRsClient.getMatch(uuid);
    if (detailResult.isErr()) {
      return Result.errFrom(detailResult);
    }
    final detail = detailResult.unwrap();
    if (!_detailIsUspsa(detail)) {
      return Result.err(
        UnsupportedMatchType("Not a USPSA match (Hitfacto.rs)"),
      );
    }

    final rowsResult = await HitfactoRsClient.getAllResults(uuid);
    if (rowsResult.isErr()) {
      return Result.errFrom(rowsResult);
    }

    return HitfactoRsMatchConverter.toShootingMatch(
      detail: detail,
      resultRows: rowsResult.unwrap(),
      options: opts,
      sourceIds: [uuid],
      sourceCode: code,
    );
  }

  bool _detailIsUspsa(HitfactoRsMatchDetail detail) {
    final t = detail.matchType?.toLowerCase() ?? "";
    final st = detail.matchSubtype?.toLowerCase() ?? "";
    return t == "uspsa_p" || st == "uspsa";
  }

  @override
  Future<Result<ShootingMatch, MatchSourceError>> getMatchFromId(
    String id, {
    SportType? typeHint,
    Sport? sport,
    HitfactoRsMatchFetchOptions? options,
  }) async {
    var clean = id;
    if (clean.startsWith("$hitfactoRsCode:")) {
      clean = removeCode(clean);
    }
    return getMatchFromSearch(
      MatchSearchResult<HitfactoRsMatchType>(
        matchName: "",
        matchId: clean,
        matchSubtype: "uspsa",
        matchType: HitfactoRsMatchType.uspsaHitFactor,
      ),
      typeHint: typeHint,
      sport: sport,
      options: options,
    );
  }
}
