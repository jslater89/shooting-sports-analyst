/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:isar_community/isar.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';

sealed class MatchQueryElement {
  String get index;
  String get property;
  List<WhereClause>? get whereClauses;
  FilterOperation? get filterCondition;
}

class TextSearchQuery extends MatchQueryElement {
  String get index => AnalystDatabase.eventNamePartsIndex;
  String get property => "eventNameParts";

  bool get canWhere => true;

  List<WhereClause>? get whereClauses {
    return [
      for(var term in terms)
        IndexWhereClause.between(indexName: index, lower: [term], upper: ['$term\u{FFFFF}']),
    ];
  }

  FilterOperation? get filterCondition {
    return FilterGroup.or(terms.map((t) => FilterCondition.startsWith(property: property, value: t, caseSensitive: false)).toList());
  }

  List<String> terms;

  TextSearchQuery(this.terms);

}

class NameSortQuery extends MatchQueryElement {
  String get index => AnalystDatabase.eventNameIndex;
  String get property => "eventName";

  bool get canWhere => true;

  List<WhereClause>? get whereClauses => [IndexWhereClause.any(indexName: index)];

  FilterOperation? get filterCondition => null;
}

class NamePartsQuery extends MatchQueryElement {
  String name;

  String get index => AnalystDatabase.eventNamePartsIndex;
  String get property => canWhere ? "eventNameParts" : "eventName";

  bool get canWhere => name.split(" ").length <= 1;

  bool get hasSearchTerms => name.isNotEmpty;

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

class SportQuery extends MatchQueryElement {
  String get index => AnalystDatabase.sportNameIndex;
  String get property => "sportName";

  List<Sport> sports;

  SportQuery(this.sports);

  bool get canWhere => true;

  @override
  FilterOperation? get filterCondition {
    return FilterGroup.or(sports.map((s) => FilterCondition.equalTo(property: property, value: s.name)).toList());
  }

  @override
  List<WhereClause>? get whereClauses => sports.map((s) => IndexWhereClause.equalTo(indexName: index, value: [s.name])).toList();
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
