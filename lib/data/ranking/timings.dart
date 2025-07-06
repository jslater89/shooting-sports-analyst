/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

class Timings {
  static const enabled = true;

  static Timings? _instance;

  factory Timings() {
    if(_instance == null) _instance = Timings._();
    return _instance!;
  }

  Timings._() {
    for(var e in elements) {
      _addToMap(e);
    }
  }

  void _addToMap(TimingElement e) {
    if(_elementsByType.containsKey(e.type)) {
      throw Exception("Duplicate timing type: ${e.type}");
    }
    _elementsByType[e.type] = e;
    for(var c in e.children) {
      _addToMap(c);
    }
  }

  Map<TimingType, TimingElement> _elementsByType = {};

  List<TimingElement> elements = [
    TimingElement(TimingType.retrieveMatches),
    TimingElement(TimingType.addShooters),
    TimingElement(TimingType.dedupShooters),
    TimingElement(TimingType.rateMatches, [
      TimingElement(TimingType.getShootersAndScores),
      TimingElement(TimingType.calcMatchStrength),
      TimingElement(TimingType.calcConnectedness),
      TimingElement(TimingType.rateShooters, [
        TimingElement(TimingType.pubstomp),
        TimingElement(TimingType.scoreMap),
        TimingElement(TimingType.update, [
          TimingElement(TimingType.calcExpected),
          TimingElement(TimingType.updateRatings),
          TimingElement(TimingType.printInfo),
        ]),
        TimingElement(TimingType.changeMap),
        TimingElement(TimingType.updateConnectedness),
      ])
    ]),
    TimingElement(TimingType.persistRatingChanges, [
      TimingElement(TimingType.loadEvents),
      TimingElement(TimingType.applyChanges),
      TimingElement(TimingType.updateDbRatings, [
        TimingElement(TimingType.dbRatingUpdateTransaction, [
          TimingElement(TimingType.saveDbRating),
          TimingElement(TimingType.persistEvents, [
            TimingElement(TimingType.getEventMatches),
          ])
        ]),
        TimingElement(TimingType.cacheUpdatedRatings),
      ]),
    ]),
    TimingElement(TimingType.removeUnseenShooters),
  ];

  void reset() {
    for(var e in elements) {
      e.reset();
    }

    ratingEventCount = 0;
    matchEntryCount = 0;
    shooterCount = 0;
    matchCount = 0;
    wallTime = 0;
  }

  void add(TimingType type, int microseconds) {
    if(type == TimingType.wallTime) {
      wallTime += microseconds;
    }
    else {
      _elementsByType[type]!.microseconds += microseconds;
    }
  }

  double get sum => elements.fold(0.0, (previousValue, element) => previousValue + element.microseconds);
  int ratingEventCount = 0;
  int matchEntryCount = 0;
  int shooterCount = 0;
  int matchCount = 0;
  int wallTime = 0;

  @override
  String toString() {
    var content = "TIMINGS:\n";
    content += elements.map((e) => e.asString(0)).join("");
    content += "Wall time: ${(wallTime / 1000).toStringAsFixed(1)} ms, ${((wallTime / 1000) / ratingEventCount).toStringAsFixed(3)} ms per rating event\n";
    content += "vs. sum: ${(sum / 1000).toStringAsFixed(1)} ms, ${((sum / 1000) / ratingEventCount).toStringAsFixed(3)} ms per rating event\n";
    content += "Total of $shooterCount shooters, $matchCount matches, $matchEntryCount match entries, and $ratingEventCount rating events";

    return content;
  }
}

enum TimingType {
  retrieveMatches,
  addShooters,
  dedupShooters,
  rateMatches,
  getShootersAndScores,
  calcMatchStrength,
  calcConnectedness,
  rateShooters,
  pubstomp,
  scoreMap,
  update,
  calcExpected,
  updateRatings,
  printInfo,
  changeMap,
  updateConnectedness,
  persistRatingChanges,
  loadEvents,
  applyChanges,
  updateDbRatings,
  dbRatingUpdateTransaction,
  cacheUpdatedRatings,
  saveDbRating,
  persistEvents,
  getEventMatches,
  removeUnseenShooters,
  wallTime;

  String get label => switch(this) {
    TimingType.retrieveMatches => "Retrieve matches",
    TimingType.addShooters => "Add shooters",
    TimingType.dedupShooters => "Dedup shooters",
    TimingType.rateMatches => "Rate matches",
    TimingType.getShootersAndScores => "Get shooters/scores",
    TimingType.calcMatchStrength => "Calc match strength",
    TimingType.calcConnectedness => "Calc connectedness",
    TimingType.rateShooters => "Rate shooters",
    TimingType.pubstomp => "Pubstomp",
    TimingType.scoreMap => "Score map",
    TimingType.update => "Update",
    TimingType.calcExpected => "Calc expected",
    TimingType.updateRatings => "Update ratings",
    TimingType.printInfo => "Print info",
    TimingType.changeMap => "Change map",
    TimingType.updateConnectedness => "Update connectedness",
    TimingType.persistRatingChanges => "Persist rating changes",
    TimingType.loadEvents => "Load rating events",
    TimingType.applyChanges => "Apply rating changes",
    TimingType.dbRatingUpdateTransaction => "DB rating update transaction",
    TimingType.cacheUpdatedRatings => "Cache updated ratings",
    TimingType.updateDbRatings => "Update DB ratings",
    TimingType.saveDbRating => "Save DB rating",
    TimingType.persistEvents => "Persist new events",
    TimingType.getEventMatches => "Get event matches",
    TimingType.removeUnseenShooters => "Remove unseen shooters",
    TimingType.wallTime => "Wall time",
  };
}

class TimingElement {
  final TimingType type;
  int microseconds = 0;
  double get milliseconds => microseconds / 1000.0;

  List<TimingElement> children = [];

  TimingElement(this.type, [this.children = const []  ]);

  void reset() {
    microseconds = 0;
    for(var c in children) {
      c.reset();
    }
  }

  String asString(int indent) {
    String indentString = "";
    for(int i = 0; i < indent; i++) indentString += "\t";
    var content = "$indentString${type.label}: ${milliseconds.toStringAsFixed(3)} ms\n";
    for(var c in children) {
      content += c.asString(indent + 1);
    }
    return content;
  }
}
