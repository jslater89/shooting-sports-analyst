// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter/foundation.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/ranking/interface/rating_data_source.dart';
import 'package:shooting_sports_analyst/data/ranking/project_settings.dart';
import 'package:shooting_sports_analyst/data/sport/model.dart';
import 'package:shooting_sports_analyst/util.dart';

/// This is a caching source for rating data, for use in
/// UI contexts where the async nature of RatingDataSource is awkward.
///
/// Calls to methods in this class will cause notifyListeners to be called when
/// new data is available in the cache.
class ChangeNotifierRatingDataSource with ChangeNotifier {
  RatingDataSource _source;

  ChangeNotifierRatingDataSource(this._source);

  /// Returns a shooter rating from the cache.
  DbShooterRating? lookupRatingByMatchEntry(MatchEntry entry) {
    var division = _groupForDivision(entry.division);
    if(division == null) return null;

    var key = _RatingCacheKey(division, entry.memberNumber);

    if(_ratingCache.containsKey(key)) return _ratingCache[key];

    _cacheRating(entry);

    return null;
  }

  Future<void> _cacheRating(MatchEntry entry) async {
    if(_ratingGroupsCache == null) {
      await _cacheRatingGroups();
    }

    var division = _groupForDivision(entry.division);
    if(division == null) {
      if(_ratingGroupsCache!.isNotEmpty) {
        division = _ratingGroupsCache!.first;
      }
      else {
        return;
      }
    }

    var ratingResult = await _source.lookupRating(division, entry.memberNumber);

    if(ratingResult.isOk()) {
      var key = _RatingCacheKey(division, entry.memberNumber);
      _ratingCache[key] = ratingResult.unwrap();
      notifyListeners();
    }
  }

  Map<_RatingCacheKey, DbShooterRating?> _ratingCache = {};

  /// Returns the rating project settings from the cache.
  RatingProjectSettings? getSettings() {
    if(_settingsCache != null) return _settingsCache;

    _cacheSettings();
    return null;
  }

  Future<void> _cacheSettings() async {
    var settingsResult = await _source.getSettings();

    if(settingsResult.isOk()) {
      _settingsCache = settingsResult.unwrap();
      notifyListeners();
    }
  }

  RatingProjectSettings? _settingsCache;

  /// Get the rating groups for the project.
  List<RatingGroup>? getGroups() {
    if(_ratingGroupsCache != null) return _ratingGroupsCache;

    _cacheRatingGroups();
    return null;
  }

  Future<void> _cacheRatingGroups() async {
    var groupsResult = await _source.getGroups();
    if(groupsResult.isOk()) {
      _ratingGroupsCache = groupsResult.unwrap();
      notifyListeners();
    }
  }

  List<RatingGroup>? _ratingGroupsCache;

  RatingGroup? _groupForDivision(Division? d) {
    if(d == null && _ratingGroupsCache != null) return _ratingGroupsCache!.first;

    if(d != null) {
      for(var g in _ratingGroupsCache!) {
        if(g.divisionNames.contains(d.name)) return g;
      }
    }

    return null;
  }

  List<DbShooterRating>? getRatings(RatingGroup group) {
    if(_ratingsCache[group] != null) return _ratingsCache[group]!;

    _cacheRatings(group);
    return null;
  }

  Future<void> _cacheRatings(RatingGroup group) async {
    var ratingsResult = await _source.getRatings(group);

    if(ratingsResult.isOk()) {
      _ratingsCache[group] = ratingsResult.unwrap();
      notifyListeners();
    }
  }

  Map<RatingGroup, List<DbShooterRating>> _ratingsCache = {};
}

class _RatingCacheKey {
  String memberNumber;
  RatingGroup division;

  _RatingCacheKey(this.division, this.memberNumber);

  @override
  int get hashCode => combineHashes(memberNumber.hashCode, division.hashCode);

  @override
  bool operator ==(Object other) {
    if(!(other is _RatingCacheKey)) return false;

    return this.memberNumber == other.memberNumber && this.division == other.division;
  }
}
