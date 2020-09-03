
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

class SearchQueryElement {
  Classification classification;
  Division division;
  PowerFactor powerFactor;
  String name;

  bool matchesShooter(Shooter s) {
    if(classification != null && s.classification != classification) return false;
    if(division != null && s.division != division) return false;
    if(powerFactor != null && s.powerFactor != powerFactor) return false;
    if(name != null && !s.getName().toLowerCase().startsWith(name) && !s.lastName.toLowerCase().startsWith(name)) return false;

    return true;
  }

  @override
  String toString() {
    return "$classification $division $powerFactor '$name'";
  }
}

List<SearchQueryElement> parseQuery(String query) {
  query = query.toLowerCase();
  query = query.replaceAll('?', '');
  List<String> groups = query.split("or");

  List<SearchQueryElement> elements = [];

  for(String group in groups) {
    group = group.trim();
    SearchQueryElement element = _parseGroup(group);
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

SearchQueryElement _parseGroup(String group) {
  List<String> items = group.split("and");

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
      debugPrint("Bad item: $item");
      return null;
    }
  }

  return element;
}

PowerFactor _matchPowerFactor(String query) {
  if(query.startsWith("maj")) return PowerFactor.major;
  else if(query.startsWith("min")) return PowerFactor.minor;
  else return null;
}

Division _matchDivision(String query) {
  query.replaceAll(RegExp(r"\s"), '');

  if(query.startsWith("pc")) return Division.pcc;
  else if(query.startsWith("pi")) return Division.pcc;
  else if(query.startsWith("op")) return Division.open;
  else if(query.startsWith(RegExp("l.*1"))) return Division.limited10;
  else if(query.startsWith("li")) return Division.limited;
  else if(query.startsWith("ca")) return Division.carryOptics;
  else if(query.startsWith("co")) return Division.carryOptics;
  else if(query.startsWith("si")) return Division.singleStack;
  else if(query.startsWith("ss")) return Division.singleStack;
  else if(query.startsWith("pr")) return Division.production;
  else if(query.startsWith("re")) return Division.revolver;
  else return null;
}