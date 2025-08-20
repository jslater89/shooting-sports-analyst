/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:collection/collection.dart';
import 'package:cookie_store/cookie_store.dart';
import 'package:html_unescape/html_unescape_small.dart';
import 'package:shooting_sports_analyst/data/match_cache/registration_cache.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:http/http.dart' as http;
import 'package:shooting_sports_analyst/data/source/practiscore_report.dart';
import 'package:shooting_sports_analyst/data/sport/model.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/util.dart';

var _log = SSALogger("RegistrationParser");

const bool verbose = false;

typedef RegistrationResult = Result<RegistrationContainer, ResultErr>;

enum RegistrationError implements ResultErr {
  badUrl,
  noCredentials,
  noMatchId,
  networkError;

  @override
  String get message => switch(this) {
    badUrl => "Bad URL",
    noCredentials => "No credentials",
    noMatchId => "No match ID",
    networkError => "Network error",
  };
}

class RegistrationContainer {
  final String name;
  final String matchId;
  final Map<Registration, ShooterRating> registrations;
  final List<Registration> unmatchedShooters;

  RegistrationContainer(
    this.name,
    this.matchId,
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

Future<RegistrationResult> getRegistrations(Sport sport, String url, List<Division> divisions, List<ShooterRating> knownShooters, {bool allowCached = true}) async {
  if(!url.endsWith("squadding")) {
    _log.i("Wrong URL");
    return RegistrationResult.err(RegistrationError.badUrl);
  }

  // Urls look like [https://]practiscore.com/match-id/[register|squadding[/printhtml]]
  var urlParts = url.split("/");
  var matchId = "";
  var nextIsId = false;
  for(var part in urlParts) {
    if(nextIsId) {
      matchId = part;
      break;
    }
    if(part.toLowerCase().contains("practiscore.com")) {
      nextIsId = true;
    }
  }
  if(matchId.isEmpty) {
    _log.w("No match ID found in $url");
  }

  if(allowCached) {
    var cached = await RegistrationCache().get(url);
    if(cached != null && cached.isNotEmpty) {
      _log.i("Using cached registration for $url");
      return RegistrationResult.ok(_parseRegistrations(sport, matchId, cached, divisions, knownShooters));
    }
  }
  try {
    var authenticated = await PractiscoreHitFactorReportParser.authenticate();
    if(!authenticated) {
      _log.e("No PS credentials available");
      return RegistrationResult.err(RegistrationError.noCredentials);
    }

    var uri = Uri.parse(url);
    var cookies = practiscoreCookies.getCookiesForRequest("practiscore.com", uri.path);
    var response = await http.get(uri, headers: {
      "Cookie": CookieStore.buildCookieHeader(cookies),
    });
    if(response.statusCode < 400) {
      var responseHtml = response.body;
      var processedHtml = _processRegistrationHtml(responseHtml);

      _log.d("Retrieved ${processedHtml.length} bytes of registrations, processed to ${responseHtml.length} bytes");

      // Cache regardless of allowCached, so that new data gets
      // cached.
      RegistrationCache().put(url, processedHtml);
      return RegistrationResult.ok(_parseRegistrations(sport, matchId, processedHtml, divisions, knownShooters));
    }
    else {
      _log.e("Failed to get registration URL: ${response.statusCode}: ${response.body}");
    }
  } catch(e, st) {
    _log.e("Failed to get registration", error: e, stackTrace: st);
  }
  return RegistrationResult.err(RegistrationError.networkError);
}

String _processRegistrationHtml(String registrationHtml) {
  // registrationHtml = registrationHtml.replaceAll("\n", "");
  registrationHtml = registrationHtml.replaceAll(RegExp(r"\s{4,}"), " ");
  return registrationHtml;
}

RegistrationContainer _parseRegistrations(
  Sport sport, String matchId, String registrationHtml, List<Division> divisions, List<ShooterRating> knownShooters
) {
  var ratings = <Registration, ShooterRating>{};
  var unmatched = <Registration>[];

  var matchName = "unnamed match";

  // Match a line
  var shooterRegex = RegExp(r'title="(?<name>.*?)\s+\((?<division>[\w\s]+?)(\s+\/\s+(?<class>\w+?))?\)"');
  var matchRegex = RegExp(r'<meta\s+property="og:title"\s+content="(?<matchname>.*)"\s*/>');
  var unescape = HtmlUnescape();
  var lines = registrationHtml.split("\n");
  for(var line in lines) {
    var nameMatch = matchRegex.firstMatch(line);
    if(nameMatch != null) {
      matchName = nameMatch.namedGroup("matchname")!;
      _log.d("Match name: $matchName");
      break;
    }
  }

  var allowUnknownClass = matchName.toLowerCase().contains("ipsc");

  int regexMatches = 0;
  for(var line in lines) {
    var matches = shooterRegex.allMatches(line);
    for(var match in matches) {
      regexMatches += 1;

      if(match.end - match.start > 250) {
        _log.w("Suspiciously long regex match: ${match.end - match.start} bytes");
        continue;
      }
      var shooterName = unescape.convert(match.namedGroup("name")!);

      if(shooterName.contains("\n")) {
        _log.w("Skipping shooter name containing newline: $shooterName");
        continue;
      }
      var d = sport.divisions.lookupByName(match.namedGroup("division")!);

      if(d == null || !divisions.contains(d)) {
        if(verbose) {
          _log.v("Skipping division not of interest: $d");
        }
        continue;
      }

      var classification = sport.classifications.lookupByName(match.namedGroup("class"));
      if(classification == null && !allowUnknownClass) {
        if(verbose) {
          _log.v("Skipping unknown classification: $shooterName");
        }
        continue;
      }

      var fallbackClassification = sport.classifications.fallback()!;

      var foundShooter = _findShooter(shooterName, null, knownShooters);

      if(foundShooter != null && !ratings.containsValue(foundShooter)) {
        ratings[Registration(name: shooterName, division: d, classification: classification ?? fallbackClassification)] = foundShooter;
      }
      else {
        _log.d("Missing shooter for: $shooterName");
        unmatched.add(
          Registration(name: shooterName, division: d, classification: classification ?? fallbackClassification)
        );
      }
    }
  }

  _log.d("Found ${ratings.length} registrations from $regexMatches matches");

  return RegistrationContainer(matchName, matchId, ratings, unmatched);
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

ShooterRating? _findShooter(String shooterName, Classification? classification, List<ShooterRating> knownShooters) {
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
