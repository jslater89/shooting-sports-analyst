/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:isar/isar.dart';
import 'package:shooting_sports_analyst/data/database/schema/match.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/db_relative_score.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_change.dart';
import 'package:sprintf/sprintf.dart';

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
  
  /// A list of strings, each representing a line of extra information about this rating
  /// event, typically defined by the rating system.
  /// 
  /// Use [infoData] to fill in the data for each line: substrings like {{key}} will be
  /// replaced with the relevant data from the element keyed by 'key' in [infoData].
  List<String> infoLines;
  /// A list of info elements, each containing data that can be filled into infoLines.
  List<RatingEventInfoElement> infoData;

  @ignore
  Map<String, dynamic> extraData;
  String get extraDataAsJson => extraData.isEmpty ? "{}" : jsonEncode(extraData);
  set extraDataAsJson(String v) => v == "{}" ? {} : extraData = jsonDecode(v);
  
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
    this.infoData = const [],
    this.infoLines = const [],
    int doubleDataElements = 0,
    int intDataElements = 0,
  }) :
    intData = List.filled(intDataElements, 0, growable: true),
    doubleData = List.filled(doubleDataElements, 0.0, growable: true) {
      if(info.isNotEmpty) {

      }
    }

  DbRatingEvent copy() {
    var event =  DbRatingEvent(
      ratingChange: this.ratingChange,
      oldRating: this.oldRating,
      infoLines: []..addAll(this.infoLines),
      infoData: []..addAll(this.infoData),
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

extension RatingEventInfoElements on String {
  static final _regex = RegExp(r"\{\{(\w+)\}\}");
  String apply(List<RatingEventInfoElement> infoData) {
    List<String> keys = [];
    for(var match in _regex.allMatches(this)) {
      keys.add(match.group(1)!);
    }
    var out = this;
    for(var key in keys) {
      var element = infoData.firstWhereOrNull((e) => e.name == key);
      out = out.replaceFirst("{{$key}}", element.toString());
    }
    return out;
  }
}

@embedded
class RatingEventInfoElement {
  String name;
  int? intValue;
  double? doubleValue;
  String? numberFormat;
  String? stringValue;
  @enumerated
  RatingEventInfoType type;

  /// Constructor for DB use. Prefer one of the typed constructors
  /// [DbRatingEventInfoElement.int], [DbRatingEventInfoElement.double],
  /// or [DbRatingEventInfoElement.string].
  RatingEventInfoElement({
    this.name = "",
    this.type = RatingEventInfoType.string,
    this.stringValue = "",
    this.intValue,
    this.doubleValue,
    this.numberFormat,
  });

  /// An info element holding an integer value.
  RatingEventInfoElement.int({
    required this.name,
    required this.intValue,
    this.numberFormat,
  }) : type = RatingEventInfoType.int;

  /// An info element holding a double value.
  RatingEventInfoElement.double({
    required this.name,
    required this.doubleValue,
    this.numberFormat,
  }) : type = RatingEventInfoType.double;

  /// An info element holding a string value.
  RatingEventInfoElement.string({
    required this.name,
    required this.stringValue,
  }) : type = RatingEventInfoType.string;

  String toString() {
    switch(type) {
      case RatingEventInfoType.int:
        if(numberFormat != null) {
          return sprintf(numberFormat!, [intValue!]);
        }
        else {
          return "$intValue!";
        }
      case RatingEventInfoType.double:
        if(numberFormat != null) {
          return sprintf(numberFormat!, [doubleValue!]);
        }
        else {
          return "$doubleValue!";
        }
      case RatingEventInfoType.string:
        return stringValue!;
    }
  }
}

enum RatingEventInfoType {
  int,
  double,
  string,
}
