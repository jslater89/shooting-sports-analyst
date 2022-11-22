
import 'package:flutter/foundation.dart';
import 'package:uspsa_result_viewer/data/model.dart';

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

class SearchQueryElement {
  USPSAClassification? classification;
  USPSADivision? division;
  PowerFactor? powerFactor;
  String? name;

  bool matchesShooter(Shooter? s) {
    if(classification != null && s!.classification != classification) return false;
    if(division != null && s!.division != division) return false;
    if(powerFactor != null && s!.powerFactor != powerFactor) return false;
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

  // After splitting by 'or', replace the literal0,1,... placeholders
  // with their original values.
  for(int i = 0; i < groups.length; i++) {
    groups[i] = _replaceLiterals(groups[i], replacements: replacements);
  }

  List<SearchQueryElement> elements = [];

  for(String group in groups) {
    group = group.trim();
    SearchQueryElement? element = _parseGroup(group);
    if(element == null) {
      debugPrint("Bad element: $group");
      return null;
    }
    else {
      elements.add(element);
    }
  }

  //debugPrint("Elements: $elements");
  return elements;
}

SearchQueryElement? _parseGroup(String group) {
  var replacements = _replaceQuotedStrings(group);
  // Split the string including replaced literals
  List<String> items = replacements.modifiedString.split("and");

  // After splitting by 'or', replace the literal0,1,... placeholders
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
      element.classification = USPSAClassificationFrom.string(item);
    }
    else {
      debugPrint("Bad item: $item");
      return null;
    }
  }

  return element;
}

_LiteralReplacement _replaceQuotedStrings(String query) {
  // Replace quoted strings with 'literal0', 'literal1', etc.
  // so that names including the string 'or' don't screw up the
  // splitter/query parser
  RegExp literalRegex = RegExp(r'"[^"]*"');
  Map<String, String> literals = {};
  int literalCount = 0;
  literalRegex.allMatches(query).forEach((element) {
    var token = "literal$literalCount";
    literals[token] = element.input.substring(element.start, element.end);
    literalCount += 1;
  });

  for(int i = 0; i < literalCount; i++) {
    var token = "literal$i";
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

USPSADivision? _matchDivision(String query) {
  query.replaceAll(RegExp(r"\s"), '');

  if(query.startsWith("pc")) return USPSADivision.pcc;
  else if(query.startsWith("pi")) return USPSADivision.pcc;
  else if(query.startsWith("op")) return USPSADivision.open;
  else if(query.startsWith(RegExp("l.*1"))) return USPSADivision.limited10;
  else if(query.startsWith("li")) return USPSADivision.limited;
  else if(query.startsWith("ca")) return USPSADivision.carryOptics;
  else if(query.startsWith("co")) return USPSADivision.carryOptics;
  else if(query.startsWith("si")) return USPSADivision.singleStack;
  else if(query.startsWith("ss")) return USPSADivision.singleStack;
  else if(query.startsWith("pr")) return USPSADivision.production;
  else if(query.startsWith("re")) return USPSADivision.revolver;
  else return null;
}