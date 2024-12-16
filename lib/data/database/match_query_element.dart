/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:isar/isar.dart';
import 'package:shooting_sports_analyst/data/database/match/match_database.dart';

sealed class MatchQueryElement {
  String get index;
  String get property;
  List<WhereClause>? get whereClauses;
  FilterOperation? get filterCondition;
}

class NamePartsQuery extends MatchQueryElement {
  String name;

  String get index => AnalystDatabase.eventNameIndex;
  String get property => canWhere ? "eventNameParts" : "eventName";

  bool get canWhere => name.split(" ").length <= 1;

  List<WhereClause>? get whereClauses {
    if (!canWhere) return null;

    return [_clauseForString(name)];
  }

  WhereClause _clauseForString(String name) {
    return IndexWhereClause.between(
      indexName: index,
      lower: [name],
      upper: ['$name\u{FFFFF}'],
    );
  }

  FilterOperation get filterCondition {
    var parts = name.split(" ");

    if (parts.length > 1) {
      return FilterCondition.contains(
        property: property,
        value: name,
        caseSensitive: false,
      );
    }
    else {
      return FilterCondition.startsWith(
        property: property,
        value: name,
        caseSensitive: false,
      );
    }
  }

  NamePartsQuery(this.name);
}

class DateQuery extends MatchQueryElement {
  String get index => AnalystDatabase.dateIndex;
  String get property => "date";

  DateTime? before;
  DateTime? after;

  /// Build a date query element.
  DateQuery({this.after, this.before});

  List<WhereClause>? get whereClauses {
    if(after != null && before != null) {
      return [IndexWhereClause.between(
        indexName: index,
        lower: [after!],
        upper: [before!],
      )];
    }
    else if (after != null) {
      return [IndexWhereClause.greaterThan(
          indexName: index,
          lower: [after!]
      )];
    }
    else if (before != null) {
      return [IndexWhereClause.lessThan(
          indexName: index,
          upper: [before!]
      )];
    }
    else {
      return [IndexWhereClause.any(
        indexName: index,
      )];
    }
  }

  FilterCondition? get filterCondition {
    if(after != null && before != null) {
      return FilterCondition.between(
        property: property,
        includeLower: true,
        includeUpper: true,
        lower: after,
        upper: before,
      );
    }
    else if(after != null) {
      return FilterCondition.greaterThan(
        property: property,
        include: true,
        value: after,
      );
    }
    else if(before != null) {
      return FilterCondition.lessThan(
        property: property,
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
  String get index => "";
  String get property => "matchLevelName";

  String name;

  LevelNameQuery(this.name);

  @override
  FilterCondition? get filterCondition {
    return FilterCondition.equalTo(property: property, value: name);
  }

  @override
  List<WhereClause>? get whereClauses => null;
}

sealed class MatchSortField {
  final bool desc;
  const MatchSortField({required this.desc});
}

class NameSort extends MatchSortField {
  const NameSort({super.desc = false});
}

class DateSort extends MatchSortField {
  const DateSort({super.desc = true});
}