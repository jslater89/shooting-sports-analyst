/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:isar/isar.dart';
import 'package:uspsa_result_viewer/data/database/match_database.dart';

sealed class MatchQueryElement {
  List<WhereClause>? get whereClauses;
  FilterOperation? get filterCondition;
}

class NamePartsQuery extends MatchQueryElement {
  String name;

  bool get canWhere => name.split(" ").length == 1;

  List<WhereClause>? get whereClauses {
    if (!canWhere) return null;

    return [_clauseForString(name)];
  }

  WhereClause _clauseForString(String name) {
    return IndexWhereClause.between(
      indexName: MatchDatabase.eventNameIndex,
      lower: [name],
      upper: ['$name\u{FFFFF}'],
    );
  }

  FilterOperation get filterCondition {
    var parts = name.split(" ");

    if (parts.length > 1) {
      return FilterCondition.contains(
        property: 'eventName',
        value: name,
        caseSensitive: false,
      );
    }
    else {
      return FilterCondition.startsWith(
        property: 'eventNameParts',
        value: name,
        caseSensitive: false,
      );
    }
  }

  NamePartsQuery(this.name);
}

class DateQuery extends MatchQueryElement {
  DateTime? before;
  DateTime? after;

  /// Build a date query element.
  DateQuery({this.after, this.before});

  List<WhereClause>? get whereClauses {
    if(after != null && before != null) {
      return [IndexWhereClause.between(
        indexName: MatchDatabase.dateIndex,
        lower: [after!],
        upper: [before!],
      )];
    }
    else if (after != null) {
      return [IndexWhereClause.greaterThan(
          indexName: MatchDatabase.dateIndex,
          lower: [after!]
      )];
    }
    else if (before != null) {
      return [IndexWhereClause.lessThan(
          indexName: MatchDatabase.dateIndex,
          upper: [before!]
      )];
    }
    else {
      return [IndexWhereClause.any(
        indexName: MatchDatabase.dateIndex,
      )];
    }
  }

  FilterCondition? get filterCondition {
    if(after != null && before != null) {
      return FilterCondition.between(
        property: 'date',
        includeLower: true,
        includeUpper: true,
        lower: after,
        upper: before,
      );
    }
    else if(after != null) {
      return FilterCondition.greaterThan(
        property: 'date',
        include: true,
        value: after,
      );
    }
    else if(before != null) {
      return FilterCondition.lessThan(
        property: 'date',
        include: true,
        value: before,
      );
    }
    else {
      return null;
    }
  }
}

class LevelNameQuery extends MatchQueryElement {
  String name;

  LevelNameQuery(this.name);

  @override
  FilterCondition? get filterCondition {
    return FilterCondition.equalTo(property: 'matchLevelName', value: name);
  }

  @override
  List<WhereClause>? get whereClauses => null;
}