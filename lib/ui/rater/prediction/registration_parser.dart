import 'package:collection/collection.dart';
import 'package:uspsa_result_viewer/data/match/shooter.dart';
import 'package:uspsa_result_viewer/data/ranking/model/shooter_rating.dart';
import 'package:http/http.dart' as http;

Future<List<ShooterRating>?> getRegistrations(String url, List<Division> divisions, List<ShooterRating> knownShooters) async {
  if(!url.endsWith("printhtml")) {
    print("Wrong URL");
    return null;
  }

  try {
    var response = await http.get(Uri.parse(url));
    if(response.statusCode < 400) {
      var responseHtml = response.body;
      var shooters = _parseRegistrations(responseHtml, divisions, knownShooters);
      return shooters;
    }
    else {
      print("Failed to get registration URL: $response");
    }
  } catch(e) {
    print("Failed to get registration: $e");
  }
  return null;
}

List<ShooterRating> _parseRegistrations(String registrationHtml, List<Division> divisions, List<ShooterRating> knownShooters) {
  var ratings = <ShooterRating>[];

  // Match a line
  var shooterRegex = RegExp(r"\d+\.\s+(?<name>.*)\s+\((?<division>\w+)\s+\/\s+(?<class>\w+)\)");
  for(var line in registrationHtml.split("\n")) {
    var match = shooterRegex.firstMatch(line);
    if(match != null) {
      var shooterName = match.namedGroup("name")!;
      var d = DivisionFrom.string(match.namedGroup("division")!);

      if(!divisions.contains(d)) continue;

      var classification = ClassificationFrom.string(match.namedGroup("class")!);
      var processedName = _processRegistrationName(shooterName);
      var foundShooter = _findShooter(processedName, classification, knownShooters);

      if(foundShooter != null) {
        ratings.add(foundShooter);
      }
      else {
        print("Missing shooter for: $processedName");
      }
    }
  }

  return ratings;
}

String _processRegistrationName(String name) {
  return name.toLowerCase().split(RegExp(r"\s+")).join();
}

List<String> _processShooterName(Shooter shooter) {
  return [
    shooter.firstName.toLowerCase().replaceAll(" ", ""),
    shooter.lastName.toLowerCase().replaceAll(" ", "")
  ];
}

ShooterRating? _findShooter(String processedName, Classification classification, List<ShooterRating> knownShooters) {
  var firstGuess = knownShooters.firstWhereOrNull((rating) {
    return _processShooterName(rating.shooter).join() == processedName;
  });

  if(firstGuess != null) {
    return firstGuess;
  }

  var secondGuess = knownShooters.firstWhereOrNull((rating) {
    return processedName.endsWith(_processShooterName(rating.shooter)[1]) && rating.lastClassification == classification;
  });

  if(secondGuess != null) {
    return secondGuess;
  }

  return null;
}