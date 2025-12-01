/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:io';

import 'package:collection/collection.dart';
import 'package:cookie_store/cookie_store.dart';
import 'package:html/parser.dart';
import 'package:html_unescape/html_unescape_small.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/match.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/registration.dart';
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
  final String? sportName;
  final DateTime? date;
  final Map<Registration, ShooterRating> registrations;
  final List<Registration> unmatchedShooters;

  RegistrationContainer(
    this.name,
    this.matchId,
    this.registrations,
    this.unmatchedShooters,
    this.sportName,
    this.date,
  );

  FutureMatch exportFutureMatch() {
    var m = FutureMatch(
      matchId: matchId,
      eventName: name,
      date: date ?? DateTime.now(),
      sportName: sportName ?? "unknown",
      sourceCode: "",
      sourceIds: [matchId],
    );
    m.registrations.addAll(exportMatchRegistrations());
    return m;
  }

  List<MatchRegistration> exportMatchRegistrations() {
    var exported = <MatchRegistration>[];
    for(var entry in registrations.entries) {
      exported.add(MatchRegistration(
        matchId: matchId,
        entryId: entry.key.name,
        shooterName: entry.key.name,
        shooterDivisionName: entry.key.division.name,
        shooterClassificationName: entry.key.classification.name,
        shooterMemberNumbers: [entry.value.memberNumber],
        squad: entry.key.squad,
      ));
    }
    for(var entry in unmatchedShooters) {
      exported.add(MatchRegistration(
        matchId: matchId,
        entryId: entry.name,
        shooterName: entry.name,
        shooterDivisionName: entry.division.name,
        shooterClassificationName: entry.classification.name,
        squad: entry.squad,
      ));
    }
    return exported;
  }
}

class Registration {
  final String name;
  final Division division;
  final Classification classification;
  final String? squad;
  int? get squadNumber {
    var stringNumber = squad?.toLowerCase().replaceAll("squad", "").trim();
    return int.tryParse(stringNumber ?? "");
  }


  const Registration({
    required this.name,
    required this.division,
    required this.classification,
    this.squad,
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

// TODO: the registration parser is doing two things here instead of just one
// 1. Parsing out registrations from page source
// 2. Matching registrations to shooters in a rating project
// We should prefer to just parse out registrations, and build a second step
// that matches registrations to ratings.

String extractMatchIdFromUrl(String url) {
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
  return matchId;
}

Future<RegistrationResult> getRegistrations(
  Sport sport, String url,
  List<Division> divisions,
  List<ShooterRating> knownShooters,
  {
    bool allowCached = true,
  }
) async {
  if(!url.endsWith("squadding")) {
    _log.i("Wrong URL");
    return RegistrationResult.err(RegistrationError.badUrl);
  }

  // Urls look like [https://]practiscore.com/match-id/[register|squadding[/printhtml]]
  var urlParts = url.split("/");
  var matchId = extractMatchIdFromUrl(url);
  if(matchId.isEmpty) {
    _log.w("No match ID found in $url");
    return RegistrationResult.err(RegistrationError.noMatchId);
  }

  if(allowCached) {
    var cached = await RegistrationCache().get(matchId);
    if(cached != null && cached.isNotEmpty) {
      _log.i("Using cached registration for $matchId");
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
      RegistrationCache().put(matchId, processedHtml);
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

Future<RegistrationResult> getRegistrationsFromHtml({
  required String registrationHtml,
  required Sport sport,
  required String matchId,
  required List<Division> divisions,
  required List<ShooterRating> knownShooters,
  bool allowCached = false,
}) async {
  if(allowCached) {
    var cached = await RegistrationCache().get(matchId);
    if(cached != null && cached.isNotEmpty) {
      _log.i("Using cached registration for $matchId");
      return RegistrationResult.ok(_parseRegistrations(sport, matchId, cached, divisions, knownShooters));
    }
  }

  var processedHtml = _processRegistrationHtml(registrationHtml);
  RegistrationCache().put(matchId, processedHtml);

  return RegistrationResult.ok(
    _parseRegistrations(sport, matchId, registrationHtml, divisions, knownShooters, warnOnUnmatched: false)
  );
}

String _processRegistrationHtml(String registrationHtml) {
  // registrationHtml = registrationHtml.replaceAll("\n", "");
  registrationHtml = registrationHtml.replaceAll(RegExp(r"\s{4,}"), " ");
  return registrationHtml;
}

RegistrationContainer _parseRegistrations(
  Sport sport,
  String matchId,
  String registrationHtml,
  List<Division> divisions,
  List<ShooterRating> knownShooters,
  {
    bool warnOnUnmatched = false,
  }
) {
  var ratings = <Registration, ShooterRating>{};
  var unmatched = <Registration>[];

  var document = HtmlParser(registrationHtml).parse();

  var matchName = "unnamed match";
  var matchDate = practicalShootingZeroDate;
  var sportName = "unknown";

  // Match a line
  var metaTitle = document.querySelector("meta[property='og:title']");
  if(metaTitle != null) {
    matchName = metaTitle.attributes["content"]!;
    _log.d("Match name: $matchName");
  }

  var metaMatchDate = document.querySelector("meta[name='match-date']");
  if(metaMatchDate != null) {
    try {
      matchDate = programmerYmdFormat.parse(metaMatchDate.attributes["content"]!);
    }
    catch(e) {
      _log.w("Unable to parse match date: ${metaMatchDate.attributes["content"]}", error: e);
    }
  }

  var metaSportName = document.querySelector("meta[name='sport-name']");
  if(metaSportName != null) {
    sportName = metaSportName.attributes["content"]!;
    _log.d("Sport name: $sportName");
  }

  var shooterRegex = RegExp(r'(?<name>.*?)\s+\((?<division>[\w\s]+?)(\s+\/\s+(?<class>\w+?))?\)');
  // var matchRegex = RegExp(r'<meta\s+property="og:title"\s+content="(?<matchname>.*)"\s*/>');
  var unescape = HtmlUnescape();

  var allowUnknownClass = matchName.toLowerCase().contains("ipsc");

  int regexMatches = 0;
  var squadElements = document.querySelectorAll("div.squadBox");

  for(var squadElement in squadElements) {
    // Extract squad label/number from the first <strong> within the squad box
    var squadLabel = squadElement.querySelector("strong")?.text.trim() ?? "";
    var squadNumberMatch = RegExp(r"\d+").firstMatch(squadLabel);
    var squadNumber = squadNumberMatch != null ? squadNumberMatch.group(0)! : squadLabel;

    var shooterElements = squadElement.querySelectorAll("span.clearable");
    _log.i("Squad $squadNumber: Found ${shooterElements.length} shooter elements");
    for(var element in shooterElements) {
      var innerSpan = element.querySelector("span");
      if(innerSpan == null) {
        String outText = element.innerHtml;
        if(outText.length > 200) {
          outText = outText.substring(0, 100) + "..." + outText.substring(outText.length - 100);
        }
        _log.w("Skipping shooter element with no inner span: $outText");
        continue;
      }
      var title = innerSpan.attributes["title"] ?? "";

      if(title.isEmpty) {
        if(!innerSpan.text.toLowerCase().contains("empty")) {
          _log.w("Unable to get title for shooter entry: ${innerSpan.outerHtml}");
        }
        continue;
      }

      var matches = shooterRegex.allMatches(title);

      if(matches.isEmpty && warnOnUnmatched) {
        _log.w("No matches found for shooter: $title");
        continue;
      }

      for(var match in matches) {
        regexMatches += 1;

        if(match.end - match.start > 250) {
          _log.w("Suspiciously long regex match: ${match.end - match.start} bytes");
          // first 100 and last 100 and last 100 characters
          var first100 = match.namedGroup("name")!.substring(0, 100);
          var last100 = match.namedGroup("name")!.substring(match.namedGroup("name")!.length - 100);
          _log.v("Suspiciously long regex match: $first100...$last100");
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

        if(foundShooter != null) {
          if(!ratings.containsValue(foundShooter)) {
            ratings[Registration(name: shooterName, division: d, classification: classification ?? fallbackClassification, squad: squadNumber)] = foundShooter;
          }
          else {
            _log.w("Duplicate shooter found: $shooterName");
          }
        }
        else {
          _log.d("Missing shooter for: $shooterName");
          unmatched.add(
            Registration(name: shooterName, division: d, classification: classification ?? fallbackClassification, squad: squadNumber)
          );
        }
      }
    }
  }

  _log.d("Found ${ratings.length} registrations from $regexMatches matches");

  return RegistrationContainer(
    matchName, matchId, ratings, unmatched, sportName, matchDate
  );
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
