import 'dart:convert';

import 'package:isar/isar.dart';
import 'package:shooting_sports_analyst/data/database/schema/match.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/db_relative_score.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_change.dart';

part 'db_rating_event.g.dart';

@collection
class DbRatingEvent implements IRatingEvent {
  Id id = Isar.autoIncrement;

  @ignore
  bool get isPersisted => id != Isar.autoIncrement;

  @Backlink(to: 'events')
  final owner = IsarLink<DbShooterRating>();

  /// The match. See [setMatch].
  final match = IsarLink<DbShootingMatch>();

  Future<void> setMatchId(String id, {bool load = false}) {
    matchId = id;
    if(load) {
      return match.load();
    }
    else {
      return Future.value();
    }
  }
  
  /// Set the match for this event, updating both the [match] link
  /// and [matchId].
  Future<void> setMatch(DbShootingMatch m, {bool save = true}) {
    matchId = m.sourceIds.first;
    match.value = m;
    if(save) {
      return match.save();
    }
    else {
      return Future.value();
    }
  }

  /// A match identifier for the match. See [setMatch].
  String matchId;

  /// The shooter's entry number in this match.
  int entryId;

  /// The stage number of this score, or -1 if this is a rating event
  /// for a full match or a match without stages.
  int stageNumber;

  DateTime date;
  double ratingChange;
  double oldRating;
  double get newRating => oldRating + ratingChange;

  /// A synthetic incrementing value used to sort rating events by date and stage
  /// number.
  @Index()
  int get dateAndStageNumber => (date.millisecondsSinceEpoch ~/ 1000) + stageNumber;

  /// Floating-point data used by specific kinds of rating events.
  List<double> doubleData;
  /// Integer data used by specific kinds of rating events.
  List<int> intData;

  // Lazily load info as much as possible, because we only care about it for display.
  @ignore
  Map<String, List<dynamic>>? _info;
  @ignore
  Map<String, List<dynamic>> get info {
    if(_info == null) {
      var data = jsonDecode(_infoAsJson) as Map<String, dynamic>;
      _info = data.cast<String, List<dynamic>>();
    }
    return _info!;
  }
  set info(Map<String, List<dynamic>> v) {
    _info = v;
  }

  String _infoAsJson = "{}";
  String get infoAsJson => _info == null ? _infoAsJson : jsonEncode(_info!);
  set infoAsJson(String v) {
    _infoAsJson = v;
  }

  @ignore
  Map<String, dynamic> extraData;
  String get extraDataAsJson => jsonEncode(extraData);
  set extraDataAsJson(String v) => extraData = jsonDecode(v);
  
  DbRelativeScore score;
  DbRelativeScore matchScore;

  DbRatingEvent({
    required this.ratingChange,
    required this.oldRating,
    this.extraData = const {},
    Map<String, List<dynamic>> info = const {},
    required this.score,
    required this.matchScore,
    required this.date,
    required this.stageNumber,
    required this.entryId,
    required this.matchId,
    int doubleDataElements = 0,
    int intDataElements = 0,
  }) :
    intData = List.filled(intDataElements, 0, growable: true),
    doubleData = List.filled(doubleDataElements, 0.0, growable: true),
    _info = info.isNotEmpty ? info : null,
    _infoAsJson = jsonEncode(info);

  DbRatingEvent copy() {
    var event =  DbRatingEvent(
      ratingChange: this.ratingChange,
      oldRating: this.oldRating,
      info: {}..addEntries(this.info.entries.map((e) => MapEntry(e.key, []..addAll(e.value)))),
      extraData: {}..addEntries(this.extraData.entries.map((e) => MapEntry(e.key, []..addAll(e.value)))),
      score: this.score.copy(),
      matchScore: this.matchScore.copy(),
      date: this.date,
      stageNumber: this.stageNumber,
      entryId: this.entryId,
      matchId: this.matchId,
    )..intData = ([]..addAll(intData))..doubleData = ([]..addAll(doubleData));

    event.match.value = this.match.value;
    event.owner.value = this.owner.value;

    return event;
  }
}