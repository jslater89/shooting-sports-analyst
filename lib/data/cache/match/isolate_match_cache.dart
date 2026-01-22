/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "dart:async";

import "package:shooting_sports_analyst/data/cache/match/match_cache.dart";
import "package:shooting_sports_analyst/data/database/schema/match.dart";
import "package:shooting_sports_analyst/data/sport/match/match.dart";
import "package:shooting_sports_analyst/util.dart";

/// A client for the isolate-based match cache, which connects to the
/// server isolate to cache and look up matches.
class IsolateMatchCacheClient implements MatchCache {
  static final IsolateMatchCacheClient _instance = IsolateMatchCacheClient._internal();
  factory IsolateMatchCacheClient() => _instance;
  IsolateMatchCacheClient._internal();

  @override
  FutureOr<bool> ready() {
    // TODO: implement ready
    throw UnimplementedError();
  }

  @override
  FutureOr<void> cache(ShootingMatch match) {
    // TODO: implement cache
    throw UnimplementedError();
  }

  @override
  FutureOr<void> clear() {
    // TODO: implement clear
    throw UnimplementedError();
  }

  @override
  FutureOr<Result<ShootingMatch, ResultErr>> get(DbShootingMatch match) {
    // TODO: implement get
    throw UnimplementedError();
  }

  @override
  FutureOr<Result<ShootingMatch, ResultErr>> getBySourceId(String sourceId) {
    // TODO: implement getBySourceId
    throw UnimplementedError();
  }

  @override
  FutureOr<void> remove(int id) {
    // TODO: implement remove
    throw UnimplementedError();
  }
}

