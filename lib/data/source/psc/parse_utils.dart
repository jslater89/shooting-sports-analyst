import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/logger.dart';

var _log = SSALogger("ParseUtils");

int jsonStringOrNumToInt(dynamic input) {
  if(input is int) {
    return input;
  }
  else if(input is String) {
    var maybeInt = int.tryParse(input);
    if(maybeInt != null) {
      return maybeInt;
    }
    var maybeDouble = double.tryParse(input);
    if(maybeDouble != null) {
      return maybeDouble.round();
    }
  }
  else if(input is num) {
    return input.round();
  }

  throw ArgumentError("$input is not a num or a num-convertible value");
}

bool matchesSport(Sport sport, {List<String> divisions = const []}) {
  // If any division looks up to a null division, the sport does not match
  return divisions.every((divisionName) {
    final division = sport.divisions.lookupByName(divisionName, fallback: false);
    if(division == null) {
      _log.v("Division $divisionName not found in sport ${sport.name}");
    }
    return division != null;
  });
}

int divisionMatchCount(Sport sport, {List<String> divisions = const []}) {
  return divisions.where((divisionName) {
    if(sport.divisions.lookupByName(divisionName, fallback: false) != null) {
      return true;
    }
    return false;
  }).length;
}

Sport? firstMatchingSport(List<Sport> sports, {List<String> divisions = const [], bool fuzzyMatching = false}) {
  if(fuzzyMatching) {
    // Find the sport that matches the most divisions
    var bestSport = null;
    var bestMatchCount = 0;
    for(var sport in sports) {
      var matchCount = divisionMatchCount(sport, divisions: divisions);
      if(matchCount > bestMatchCount) {
        bestMatchCount = matchCount;
        bestSport = sport;
      }
    }
    // TODO: maybe base this off of how many divisions matched vs provided
    if(bestSport != null) {
      _log.d("Fuzzy division match: ${bestSport.name} with ${bestMatchCount} divisions, of ${bestSport.divisions.length} in the sport and ${divisions.length} provided");
    }
    else {
      _log.d("No fuzzy division match found for provided divisions: ${divisions}");
    }
    return bestSport;
  }
  else {
    // Find the sport that matches the most divisions exactly
    for(var sport in sports) {
      if(matchesSport(sport, divisions: divisions)) return sport;
    }
  }

  return null;
}

DateTime parseUtcDate(String date) {
  if(date.endsWith("Z")) {
    return DateTime.parse(date);
  }
  else {
    return DateTime.parse("${date}Z");
  }
}
