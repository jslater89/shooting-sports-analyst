/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */


import 'package:collection/collection.dart';
import 'package:shooting_sports_analyst/data/model.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/logger.dart';

var _log = SSALogger("SearchQueryParser");

// This file parses search queries of the form
// ?revolver and b or production and c or singlestack and major or "jay slater".
// Queries begin with a question mark (to differentiate them from searches).
// AND binds tighter than OR. Items linked by an AND are a group. Groups are
// separated by OR.
// Items in quotation marks are searches by name.
// Each group can contain, at most, one classification, one division,
// one power factor, and one name.

class _LiteralReplacement {
  final String modifiedString;
  final Map<String, String> replacements;

  _LiteralReplacement({required this.modifiedString, required this.replacements});
}

/// A group of query elements linked by AND.
///
/// A query with ORs is represented as a list of [SearchQueryElement]s. A shooter matches
/// the query if any query element in the list matches the shooter.
class SearchQueryElement {
  Classification? classification;
  Division? division;
  PowerFactor? powerFactor;
  String? name;

  bool matchesShooter(Shooter? s) {
    if(classification != null && s!.classification != classification) return false;
    if(division != null && s!.division != division) return false;
    if(powerFactor != null && s!.powerFactor != powerFactor) return false;
    if(name != null && !s!.getName().toLowerCase().startsWith(name!) && !s.lastName.toLowerCase().startsWith(name!)) return false;

    return true;
  }

  bool matchesShooterRating(ShooterRating? s) {
    if(classification != null && s!.lastClassification != classification) return false;
    if(division != null && s!.division != division) return false;
    // if(powerFactor != null && s!.powerFactor != powerFactor) return false;
    if(name != null && !s!.getName().toLowerCase().startsWith(name!) && !s.lastName.toLowerCase().startsWith(name!)) return false;

    return true;
  }

  @override
  String toString() {
    return "$classification $division $powerFactor '$name'";
  }
}

List<SearchQueryElement>? parseQuery(String query) {
  query = query.toLowerCase();
  query = query.replaceFirst('?', '');

  var replacements = _replaceQuotedStrings(query);
  // Split the string including replaced literals
  List<String> groups = replacements.modifiedString.split("or");

  // After splitting by 'or', replace the literal000,001,... placeholders
  // with their original values.
  for(int i = 0; i < groups.length; i++) {
    groups[i] = _replaceLiterals(groups[i], replacements: replacements);
  }

  List<SearchQueryElement> elements = [];

  for(String group in groups) {
    group = group.trim();
    SearchQueryElement? element = _parseGroup(group);
    if(element == null) {
      _log.d("Bad element: $group");
      return null;
    }
    else {
      elements.add(element);
    }
  }

  //_log.v("Elements: $elements");
  return elements;
}

SearchQueryElement? _parseGroup(String group) {
  var replacements = _replaceQuotedStrings(group);
  // Split the string including replaced literals
  List<String> items = replacements.modifiedString.split("and");

  // After splitting by 'or', replace the literal000,001,... placeholders
  // with their original values.
  for(int i = 0; i < items.length; i++) {
    items[i] = _replaceLiterals(items[i], replacements: replacements);
  }

  if(items.length > 4) {
    return null;
  }

  SearchQueryElement element = SearchQueryElement();

  for(String item in items) {
    item = item.trim();

    var pf = _matchPowerFactor(item);
    var div = _matchDivision(item);

    if(item.startsWith('"')) {
      if(item.length == 1 || !item.endsWith('"')) {
        return null;
      }

      element.name = item.replaceAll('"', '');
    }
    else if(pf != null) {
      element.powerFactor = pf;
    }
    else if(div != null){
      element.division = div;
    }
    else if(RegExp(r"^gm$|^[mabcdu]$").hasMatch(item)) {
      element.classification = ClassificationFrom.string(item);
    }
    else {
      _log.d("Bad item: $item");
      return null;
    }
  }

  return element;
}

_LiteralReplacement _replaceQuotedStrings(String query) {
  // Replace quoted strings with 'literal000', 'literal001', etc.
  // so that names including the string 'or' don't screw up the
  // splitter/query parser
  RegExp literalRegex = RegExp(r'"[^"]*"');
  Map<String, String> literals = {};

  int literalLength = 3;
  int literalCount = 0;
  literalRegex.allMatches(query).forEachIndexed((i, element) {
    String literalComponent = "$i".padLeft(literalLength, "0");

    var token = "literal$literalComponent";
    literals[token] = element.input.substring(element.start, element.end);
    literalCount += 1;
  });

  for(int i = 0; i < literalCount; i++) {
    String literalComponent = "$i".padLeft(literalLength, "0");

    var token = "literal$literalComponent";
    var literal = literals[token]!;
    query = query.replaceFirst(literal, token);
  }

  return _LiteralReplacement(modifiedString: query, replacements: literals);
}

String _replaceLiterals(String s, {required _LiteralReplacement replacements}) {
  for(var token in replacements.replacements.keys) {
    var literal = replacements.replacements[token]!;
    s = s.replaceFirst(token, literal);
  }

  return s;
}

PowerFactor? _matchPowerFactor(String query) {
  if(query.startsWith("maj")) return PowerFactor.major;
  else if(query.startsWith("min")) return PowerFactor.minor;
  else return null;
}

Division? _matchDivision(String query) {
  query.replaceAll(RegExp(r"\s"), '');

  if(query.startsWith("pc")) return Division.pcc;
  else if(query.startsWith("pi")) return Division.pcc;
  else if(query.startsWith("op")) return Division.open;
  else if(query.startsWith(RegExp("l.*1"))) return Division.limited10;
  else if(query.startsWith("li") && !query.contains("o")) return Division.limited;
  else if(query.startsWith("li") && query.contains("o")) return Division.limitedOptics;
  else if(query.startsWith("lo")) return Division.limitedOptics;
  else if(query.startsWith("ca")) return Division.carryOptics;
  else if(query.startsWith("co")) return Division.carryOptics;
  else if(query.startsWith("si")) return Division.singleStack;
  else if(query.startsWith("ss")) return Division.singleStack;
  else if(query.startsWith("pr")) return Division.production;
  else if(query.startsWith("re")) return Division.revolver;
  else return null;
}
