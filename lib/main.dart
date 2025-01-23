/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

// ignore: avoid_web_libraries_in_flutter

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shooting_sports_analyst/config.dart';
import 'package:shooting_sports_analyst/data/database/match/analyst_database.dart';
import 'package:shooting_sports_analyst/data/match_cache/match_cache.dart';
import 'package:shooting_sports_analyst/db_oneoffs.dart';
import 'package:shooting_sports_analyst/html_or/html_or.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/route/local_upload.dart';
import 'package:shooting_sports_analyst/route/home_page.dart';
import 'package:shooting_sports_analyst/route/practiscore_url.dart';
import 'package:shooting_sports_analyst/route/ratings.dart';
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

  _log.i("=== App start ===");

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

  WidgetsFlutterBinding.ensureInitialized();

  await ConfigLoader().ready;
  initLogger();

  await AnalystDatabase().ready;
  _log.i("Database ready");

  oneoffDbAnalyses(AnalystDatabase());

  if(!HtmlOr.isWeb) {
    var path = await getApplicationSupportDirectory();
    Hive.init(path.absolute.path);

    // Start warming up the match cache immediately, since we're almost always going to want it
    matchCacheProgressCallback = (_1, _2) async {
      await Future.delayed(Duration(microseconds: 1));
    };
    MatchCache();
  }

  _log.i("Hive cache ready");

  runApp(MyApp());
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
          primarySwatch: Colors.indigo,
          visualDensity: VisualDensity.adaptivePlatformDensity,
        ),
        home: Container(),
      );
    }
    else {
      return Provider.value(
        value: _prefs!,
        child: MaterialApp(
          title: 'Shooting Sports Analyst',
          theme: ThemeData(
            useMaterial3: false,
            primarySwatch: Colors.indigo,
            visualDensity: VisualDensity.adaptivePlatformDensity,
          ),
          initialRoute: '/',
          onGenerateRoute: globals.router.generator,
        ),
      );
    }
  }
}