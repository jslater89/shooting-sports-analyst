/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

// ignore: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shooting_sports_analyst/config/config.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/help/all_helps.dart';
import 'package:shooting_sports_analyst/data/match_cache/match_cache.dart';
import 'package:shooting_sports_analyst/data/match_cache/registration_cache.dart';
import 'package:shooting_sports_analyst/data/ranking/rating_context.dart';
import 'package:shooting_sports_analyst/db_oneoffs.dart';
import 'package:shooting_sports_analyst/html_or/html_or.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/route/local_upload.dart';
import 'package:shooting_sports_analyst/route/home_page.dart';
import 'package:shooting_sports_analyst/route/practiscore_url.dart';
import 'package:shooting_sports_analyst/route/ratings.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/help/help_registry.dart';
import 'package:shooting_sports_analyst/version.dart';
import 'package:window_manager/window_manager.dart';
import 'configure_nonweb.dart' if (dart.library.html) 'configure_web.dart';
import 'package:fluro/fluro.dart' as fluro;

var _log = SSALogger("main");

class GlobalData {
  String? _resultsFileUrl;
  String? get resultsFileUrl => _resultsFileUrl;
  String? _practiscoreUrl;
  String? get practiscoreUrl => _practiscoreUrl;
  String? _practiscoreId;
  String? get practiscoreId => _practiscoreId;
  final router = fluro.FluroRouter();

  GlobalData() {
    var params = HtmlOr.getQueryParams();
    _log.v("iframe params? $params");
    _resultsFileUrl = params['resultsFile'];
    _practiscoreUrl = params['practiscoreUrl'];
    _practiscoreId = params['practiscoreId'];
  }
}

GlobalData globals = GlobalData();

void main() async {
  // dumpRatings();

  FlutterError.onError = (details) {
    _log.e("Flutter error", error: details.exceptionAsString(), stackTrace: details.stack);
  };
  runZonedGuarded(() async {
      WidgetsFlutterBinding.ensureInitialized();

    _log.i("=== App start ===");
    var info = await PackageInfo.fromPlatform();
    var localVersion = VersionInfo.version;
    var packageVersion = info.version;
    var packageBuildNumber = info.buildNumber;
    _log.i("Shooting Sports Analyst $localVersion ($packageVersion+$packageBuildNumber)");
    globals.router.define('/', transitionType: fluro.TransitionType.fadeIn, handler: fluro.Handler(
      handlerFunc: (context, params) {
        _log.d("/ route params: $params");
        return HomePage();
      }
    ));
    globals.router.define('/local', transitionType: fluro.TransitionType.fadeIn, handler: fluro.Handler(
      handlerFunc: (context, params) {
        return UploadedResultPage();
      }
    ));
    globals.router.define('/rater', transitionType: fluro.TransitionType.fadeIn, handler: fluro.Handler(
      handlerFunc: (context, params) {
        return RatingsContainerPage();
      }
    ));
    globals.router.define('/web/:sourceId/:matchId', transitionType: fluro.TransitionType.fadeIn, handler: fluro.Handler(
      handlerFunc: (context, params) {
        return PractiscoreResultPage(matchId: params['matchId']![0], sourceId: params['sourceId']![0]);
      }
    ));

    // resultUrl is base64-encoded
    globals.router.define('/webfile/:sourceId/:resultUrl', transitionType: fluro.TransitionType.fadeIn, handler: fluro.Handler(
        handlerFunc: (context, params) {
          var urlString = String.fromCharCodes(Base64Codec.urlSafe().decode(params['resultUrl']![0]));
          return PractiscoreResultPage(resultUrl: urlString, sourceId: params['sourceId']![0]);
        }
    ));
    configureApp();

    await windowManager.ensureInitialized();
    var options = WindowOptions(
      minimumSize: Size(1280, 720),
      title: "Shooting Sports Analyst",
    );
    windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });

    await ConfigLoader().ready;
    initLogger();

    await AnalystDatabase().ready;
    _log.i("Database ready");

    if(!HtmlOr.isWeb) {
      var path = await getApplicationSupportDirectory();
      Hive.init(path.absolute.path);

      // Start warming up the match cache immediately, since we're almost always going to want it
      matchCacheProgressCallback = (_1, _2) async {
        await Future.delayed(Duration(microseconds: 1));
      };
      MatchCache();
    }
    _log.i("Match cache ready");

      await RegistrationCache().ready;
    _log.i("Registration cache ready");

    oneoffDbAnalyses(AnalystDatabase());
    HelpTopicRegistry().initialize();
    registerHelpTopics();

    runApp(MyApp());
  }, (error, stack) {
    _log.e("Uncaught error", error: error, stackTrace: stack);
  });
}

class MyApp extends StatefulWidget {
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    _getPrefs();
  }

  Future<void> _getPrefs() async {
    _prefs = await SharedPreferences.getInstance();
    setState(() {

    });
  }

  SharedPreferences? _prefs;
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    if(_prefs == null) {
      return MaterialApp(
        title: 'Shooting Sports Analyst',
        theme: ThemeData(
          useMaterial3: false,
          brightness: Brightness.light,
          colorSchemeSeed: Colors.indigo,
          visualDensity: VisualDensity.adaptivePlatformDensity,
        ),
        darkTheme: ThemeData(
          useMaterial3: false,
          brightness: Brightness.dark,
          colorSchemeSeed: Colors.indigo,
          visualDensity: VisualDensity.adaptivePlatformDensity,
        ),
        // themeMode: ThemeMode.dark,
        home: Container(),
      );
    }
    else {
      return MultiProvider(
        providers: [
          Provider.value(value: _prefs!),
          ChangeNotifierProvider(create: (context) => RatingContext()),
        ],
        child: MaterialApp(
          title: 'Shooting Sports Analyst',
          theme: ThemeData(
            useMaterial3: false,
            primarySwatch: Colors.indigo,
            visualDensity: VisualDensity.adaptivePlatformDensity,
          ),
          darkTheme: ThemeData(
            useMaterial3: false,
            brightness: Brightness.dark,
            colorSchemeSeed: Colors.indigo,
            visualDensity: VisualDensity.adaptivePlatformDensity,
          ),
          // themeMode: ThemeMode.dark,
          initialRoute: '/',
          onGenerateRoute: globals.router.generator,
        ),
      );
    }
  }
}
