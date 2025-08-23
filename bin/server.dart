
import 'dart:io';

import 'package:shelf_plus/shelf_plus.dart';
import 'package:shooting_sports_analyst/config/secure_config.dart';
import 'package:shooting_sports_analyst/config/serialized_config.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/match.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/shooter_rating.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/server/fantasy/league_service.dart';
import 'package:shooting_sports_analyst/server/middleware/logger_middleware.dart';
import 'package:shooting_sports_analyst/version.dart';

final _log = SSALogger("Server Main");

Future<void> main() async {
  print("Starting server.");
  SSALogger.debugProvider = ServerDebugProvider();
  var configLoader = ConfigLoader();
  await configLoader.readyFuture;
  print("Loaded configuration.");
  initLogger(configLoader.config, ServerConfigProvider());
  _log.i("Initialized logger.");

  var database = AnalystDatabase();
  await database.ready;

  var matchCount = database.isar.dbShootingMatchs.countSync();
  var projectCount = database.isar.dbRatingProjects.countSync();
  var ratingCount = database.isar.dbShooterRatings.countSync();

  _log.i("Database contains $matchCount matches, $projectCount projects, and $ratingCount ratings.");

  _log.i("Server initialization completed.");

  shelfRun(init);
}

Handler init() {
  final app = Router().plus;
  app.use(createLoggerMiddleware());
  app.get("/", (request) => "Shooting Sports Analyst API ${VersionInfo.version}");

  var leagueService = LeagueService([createLoggerMiddleware("/league/")]);
  app.mount("/league", leagueService.router);

  return app.call;
}



class ServerDebugProvider implements DebugModeProvider {
  @override
  bool get kDebugMode => true;

  @override
  bool get kReleaseMode => false;
}

class ServerConfigProvider implements ConfigProvider {
  @override
  void addListener(void Function(SerializedConfig config) Function) {

  }
}

/// A read-only secure storage provider that reads from environment variables.
class ServerSecureStorageProvider implements SecureStorageProvider {
  @override
  Future<void> write(String key, String value) async {
    // read-only
  }

  @override
  Future<String?> read(String key) async {
    var envKey = "SSA_${key.toUpperCase()}";
    return Platform.environment[envKey];
  }

  @override
  Future<void> delete(String key) async {
    // read-only
  }
}
