/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:collection/collection.dart';
import 'package:html_unescape/html_unescape_small.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:http/http.dart' as http;
import 'package:shooting_sports_analyst/data/sport/model.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/logger.dart';

var _log = SSALogger("RegistrationParser");

class RegistrationResult {
  final String name;
  final Map<Registration, ShooterRating> registrations;
  final List<Registration> unmatchedShooters;

  RegistrationResult(
    this.name,
    this.registrations,
    this.unmatchedShooters,
  );
}

class Registration {
  final String name;
  final Division division;
  final Classification classification;

  const Registration({
    required this.name,
    required this.division,
    required this.classification
  });

  @override
  bool operator ==(Object other) {
    return (other is Registration)
        && other.name == this.name
        && other.division == this.division
        && other.classification == this.classification;
  }

  @override
  int get hashCode => name.hashCode + division.hashCode + classification.hashCode;
}

Future<RegistrationResult?> getRegistrations(Sport sport, String url, List<Division> divisions, List<ShooterRating> knownShooters) async {
  if(!url.endsWith("squadding")) {
    _log.i("Wrong URL");
    return null;
  }

  try {
    var response = await http.get(Uri.parse(url));
    if(response.statusCode < 400) {
      var responseHtml = response.body;
      return _parseRegistrations(sport, responseHtml, divisions, knownShooters);
    }
    else {
      _log.e("Failed to get registration URL: $response");
    }
  } catch(e, st) {
    _log.e("Failed to get registration", error: e, stackTrace: st);
  }
  return null;
}

RegistrationResult _parseRegistrations(Sport sport, String registrationHtml, List<Division> divisions, List<ShooterRating> knownShooters) {
  var ratings = <Registration, ShooterRating>{};
  var unmatched = <Registration>[];

  var matchName = "unnamed match";

  // Match a line
  var shooterRegex = RegExp(r'<span.*title="(?<name>.*)\s+\((?<division>[\w\s]+)\s+\/\s+(?<class>\w+)\)');
  var matchRegex = RegExp(r'<meta\s+property="og:title"\s+content="(?<matchname>.*)"\s*/>');
  var unescape = HtmlUnescape();
  for(var line in registrationHtml.split("\n")) {
    var nameMatch = matchRegex.firstMatch(line);
    if(nameMatch != null) {
      matchName = nameMatch.namedGroup("matchname")!;
      _log.d("Match name: $matchName");
    }

    var match = shooterRegex.firstMatch(line);
    if(match != null) {
      var shooterName = unescape.convert(match.namedGroup("name")!);
      var d = sport.divisions.lookupByName(match.namedGroup("division")!);

      if(d == null || !divisions.contains(d)) continue;

      var classification = sport.classifications.lookupByName(match.namedGroup("class")!);

      // TODO
      if(classification == null) continue;

      var foundShooter = _findShooter(shooterName, classification, knownShooters);

      if(foundShooter != null && !ratings.containsValue(foundShooter)) {
        ratings[Registration(name: shooterName, division: d, classification: classification)] = foundShooter;
      }
      else {
        _log.d("Missing shooter for: $shooterName");
        unmatched.add(
          Registration(name: shooterName, division: d, classification: classification)
        );
      }
    }
  }

  return RegistrationResult(matchName, ratings, unmatched);
}

String _processRegistrationName(String name) {
  return name.toLowerCase().split(RegExp(r"\s+")).join().replaceAll(RegExp(r"[^a-z]"), "");
}

List<String> _processShooterName(Shooter shooter) {
  return [
    shooter.firstName.toLowerCase().replaceAll(" ", "").replaceAll(RegExp(r"[^a-z]"), ""),
    shooter.lastName.toLowerCase().replaceAll(" ", "").replaceAll(RegExp(r"[^a-z]"), "")
  ];
}

ShooterRating? _findShooter(String shooterName, Classification classification, List<ShooterRating> knownShooters) {
  var processedName = _processRegistrationName(shooterName);
  var firstGuess = knownShooters.firstWhereOrNull((rating) {
    return _processShooterName(rating).join().replaceAll(RegExp(r"[^a-z]"), "") == processedName;
  });

  if(firstGuess != null) {
    return firstGuess;
  }

  var secondGuess = knownShooters.where((rating) {
    return processedName.endsWith(_processShooterName(rating)[1]) && rating.lastClassification == classification;
  }).toList();

  if(secondGuess.length == 1) {
    return secondGuess[0];
  }

  // Catch e.g. Robert Hall -> Rob Hall
  var thirdGuess = knownShooters.where((rating) {
    var processedShooterName = _processShooterName(rating);
    var lastName = _processRegistrationName(shooterName.split(" ").last);
    var firstName = _processRegistrationName(shooterName.split(" ").first);

    if((lastName.endsWith(processedShooterName[1]) || lastName.startsWith(processedShooterName[1]))
          && (firstName.startsWith(processedShooterName[0]) || processedShooterName[0].startsWith(firstName))
          && rating.lastClassification == classification) {
      return true;
    }
    return false;
  }).toList();

  if(thirdGuess.length == 1) {
    return thirdGuess[0];
  }

  return null;
}