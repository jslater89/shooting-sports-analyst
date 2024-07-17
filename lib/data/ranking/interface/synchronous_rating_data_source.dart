
import 'package:flutter/foundation.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/ranking/interface/rating_data_source.dart';
import 'package:shooting_sports_analyst/data/ranking/project_manager.dart';
import 'package:shooting_sports_analyst/data/sport/model.dart';
import 'package:shooting_sports_analyst/util.dart';

/// SynchronousRatingDataSource is a caching source for rating data, for use in
/// UI contexts where the async nature of RatingDataSource is awkward.
///
/// Calls to methods in this class will cause notifyListeners to be called when
/// new data is available in the cache.
class SynchronousRatingDataSource with ChangeNotifier {
  RatingDataSource _source;

  SynchronousRatingDataSource(this._source);

  /// Returns a shooter rating from the cache.
  DbShooterRating? lookupRating(MatchEntry entry) {
    if(_ratingCache.containsKey(entry)) return _ratingCache[entry];

    _cacheRating(entry);

    return null;
  }

  Future<void> _cacheRating(MatchEntry entry) async {
    var ratingResult = await _source.lookupRating(entry);

    if(ratingResult.isOk()) {
      _ratingCache[entry] = ratingResult.unwrap();
      notifyListeners();
    }
  }

  Map<MatchEntry, DbShooterRating?> _ratingCache = {};

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
    }
  }

  RatingProjectSettings? _settingsCache;
}