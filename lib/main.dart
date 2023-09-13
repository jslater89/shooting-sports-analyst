// ignore: avoid_web_libraries_in_flutter

import 'dart:convert';
import 'dart:io';
import 'dart:math';


import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
// import 'package:uspsa_result_viewer/data/db/object/match/match.dart';
// import 'package:uspsa_result_viewer/data/db/object/rating/rating_project.dart';
// import 'package:uspsa_result_viewer/data/db/project/project_db.dart';
import 'package:uspsa_result_viewer/data/match/practical_match.dart';
import 'package:uspsa_result_viewer/data/match_cache/match_cache.dart';
import 'package:uspsa_result_viewer/data/ranking/evolution/elo_tuner.dart';
import 'package:uspsa_result_viewer/data/ranking/project_manager.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/elo/elo_rater_settings.dart';
import 'package:uspsa_result_viewer/data/ranking/rating_history.dart';
import 'package:uspsa_result_viewer/html_or/html_or.dart';
import 'package:uspsa_result_viewer/route/local_upload.dart';
import 'package:uspsa_result_viewer/route/home_page.dart';
import 'package:uspsa_result_viewer/route/practiscore_url.dart';
import 'package:uspsa_result_viewer/route/ratings.dart';
import 'configure_nonweb.dart' if (dart.library.html) 'configure_web.dart';
import 'package:fluro/fluro.dart' as fluro;

import 'data/ranking/evolution/genome.dart';
import 'data/results_file_parser.dart';

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
    debugPrint("iframe params? $params");
    _resultsFileUrl = params['resultsFile'];
    _practiscoreUrl = params['practiscoreUrl'];
    _practiscoreId = params['practiscoreId'];
  }
}

GlobalData globals = GlobalData();

void main() async {
  // dumpRatings();

  globals.router.define('/', transitionType: fluro.TransitionType.fadeIn, handler: fluro.Handler(
    handlerFunc: (context, params) {
      debugPrint("$params");
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
  globals.router.define('/web/:matchId', transitionType: fluro.TransitionType.fadeIn, handler: fluro.Handler(
    handlerFunc: (context, params) {
      return PractiscoreResultPage(matchId: params['matchId']![0],);
    }
  ));

  // resultUrl is base64-encoded
  globals.router.define('/webfile/:resultUrl', transitionType: fluro.TransitionType.fadeIn, handler: fluro.Handler(
      handlerFunc: (context, params) {
        var urlString = String.fromCharCodes(Base64Codec.urlSafe().decode(params['resultUrl']![0]));
        return PractiscoreResultPage(resultUrl: urlString,);
      }
  ));
  configureApp();

  WidgetsFlutterBinding.ensureInitialized();

  if(!HtmlOr.isWeb) {
    var path = await getApplicationSupportDirectory();
    Hive.init(path.absolute.path);

    // Start warming up the match cache immediately, since we're almost always going to want it
    matchCacheProgressCallback = (_1, _2) async {
      await Future.delayed(Duration(microseconds: 1));
    };
    MatchCache();
  }

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Match Results Viewer',
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      initialRoute: '/',
      onGenerateRoute: globals.router.generator,
    );
  }
}