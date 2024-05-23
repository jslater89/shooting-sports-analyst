/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */


import 'package:collection/collection.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/shooter.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/logger.dart';

var _log = SSALogger("SearchQueryParser");

Map<Sport, SportPrefixMatcher> _matchers = {};

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

  bool matchesShooter(MatchEntry s) {
    if(classification != null && s.classification != classification) return false;
    if(division != null && s.division != division) return false;
    if(powerFactor != null && s.powerFactor != powerFactor) return false;
    if(name != null && !s.getName().toLowerCase().startsWith(name!) && !s.lastName.toLowerCase().startsWith(name!)) return false;

    return true;
  }

  bool matchesShooterRating(ShooterRating? s) {
    if(classification != null && s!.lastClassification != classification) return false;
    if(division != null && s!.division != division) return false;
    //if(powerFactor != null && s!.powerFactor != powerFactor) return false;
    if(name != null && !s!.getName().toLowerCase().startsWith(name!) && !s.lastName.toLowerCase().startsWith(name!)) return false;

    return true;
  }

  @override
  String toString() {
    return "$classification $division $powerFactor '$name'";
  }
}

List<SearchQueryElement>? parseQuery(Sport sport, String query) {
  if(_matchers[sport] == null) {
    _matchers[sport] = SportPrefixMatcher(sport);
  }
  var matcher = _matchers[sport]!;

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
    SearchQueryElement? element = _parseGroup(matcher, group);
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

SearchQueryElement? _parseGroup(SportPrefixMatcher matcher, String group) {
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

    var pf = _matchPowerFactor(matcher, item);
    var div = _matchDivision(matcher, item);
    var cls = _matchClassification(matcher, item);

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
    else if(cls != null) {
      element.classification = cls;
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

PowerFactor? _matchPowerFactor(SportPrefixMatcher matcher, String query) {
  return matcher.matchPowerFactor(query);
}

Division? _matchDivision(SportPrefixMatcher matcher, String query) {
  return matcher.matchDivision(query);
}

Classification? _matchClassification(SportPrefixMatcher matcher, String query) {
  return matcher.matchClassification(query);
}

enum PrefixMatcherType {
  division,
  classification,
  powerFactor,
}

class SportPrefixMatcher {
  final Sport sport;

  late final ShortestPrefixMatcher<Division> divisionMatcher;
  late final ShortestPrefixMatcher<Classification> classificationMatcher;
  late final ShortestPrefixMatcher<PowerFactor> powerFactorMatcher;

  SportPrefixMatcher(this.sport) {
    divisionMatcher = ShortestPrefixMatcher(sport.divisions.values.toList());
    classificationMatcher = ShortestPrefixMatcher(sport.classifications.values.toList());
    powerFactorMatcher = ShortestPrefixMatcher(sport.powerFactors.values.toList());
  }

  (ShortestPrefixMatcher, List<ShortestPrefixMatcher>) getMatchersFor(PrefixMatcherType type) {
    if(type == PrefixMatcherType.division) {
      return (divisionMatcher, [classificationMatcher, powerFactorMatcher]);
    }
    else if(type == PrefixMatcherType.classification) {
      return (classificationMatcher, [divisionMatcher, powerFactorMatcher]);
    }
    else if(type == PrefixMatcherType.powerFactor) {
      return (powerFactorMatcher, [divisionMatcher, classificationMatcher]);
    }

    throw ArgumentError();
  }

  Division? matchDivision(String name) {
    name = name.toLowerCase();
    var matcher = divisionMatcher;
    var suppressors = [classificationMatcher, powerFactorMatcher];

    var div = matcher.lookup(name);
    if(div != null) {
      for(var s in suppressors) {
        var v = s.lookup(name);
        if(v != null) {
          return null;
        }
      }

      return div;
    }

    return null;
  }

  Classification? matchClassification(String name) {
    name = name.toLowerCase();
    var matcher = classificationMatcher;
    var suppressors = [divisionMatcher, powerFactorMatcher];

    var div = matcher.lookup(name);
    if(div != null) {
      for(var s in suppressors) {
        var v = s.lookup(name);
        if(v != null) {
          return null;
        }
      }

      return div;
    }

    return null;
  }

  PowerFactor? matchPowerFactor(String name) {
    name = name.toLowerCase();
    var matcher = powerFactorMatcher;
    var suppressors = [divisionMatcher, classificationMatcher];

    var div = matcher.lookup(name);
    if(div != null) {
      for(var s in suppressors) {
        var v = s.lookup(name);
        if(v != null) {
          return null;
        }
      }

      return div;
    }

    return null;
  }
}

class ShortestPrefixMatcher<T extends NameLookupEntity> {
  /// Maps every prefix that occurs in the set of value names
  /// to one or more objects of type T.
  Map<String, Set<T>> _byPrefix = {};

  ShortestPrefixMatcher(List<T> values) {
    for(var v in values) {
      Set<String> names = {
        v.name.toLowerCase(),
        ...v.alternateNames.map((s) => s.toLowerCase()),
        v.shortName.toLowerCase(),
        v.longName.toLowerCase(),
      };

      Set<String> extraNames = {};
      for(var name in names) {
        if(name.contains(" ")) {
          var words = name.split(" ");
          var abbrev = words.map((w) => w.substring(0, 1)).reduce((value, element) => "$value$element");
          extraNames.add(abbrev);
        }
      }
      names.addAll(extraNames);

      Set<String> finalNames = {};
      for(var name in names) {
        finalNames.add(name.replaceAll(" ", ""));
      }

      for(var name in finalNames) {
        for(int i = 1; i <= name.length; i++) {
          var prefix = name.substring(0, i);
          _byPrefix[prefix] ??= {};
          _byPrefix[prefix]!.add(v);
        }
      }
    }
  }

  T? lookup(String prefix) {
    var values = _byPrefix[prefix];
    if(values != null && values.length == 1) return values.first;
    return null;
  }
}