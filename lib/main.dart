// ignore: avoid_web_libraries_in_flutter

import 'dart:convert';
import 'dart:io';


import 'package:collection/collection.dart';
import 'package:floor/floor.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uspsa_result_viewer/data/db/object/match/match.dart';
import 'package:uspsa_result_viewer/data/db/object/rating/rating_project.dart';
import 'package:uspsa_result_viewer/data/db/project/project_db.dart';
import 'package:uspsa_result_viewer/data/match/practical_match.dart';
import 'package:uspsa_result_viewer/data/match_cache/match_cache.dart';
import 'package:uspsa_result_viewer/data/ranking/project_manager.dart';
import 'package:uspsa_result_viewer/data/ranking/rating_history.dart';
import 'package:uspsa_result_viewer/html_or/html_or.dart';
import 'package:uspsa_result_viewer/route/local_upload.dart';
import 'package:uspsa_result_viewer/route/match_select.dart';
import 'package:uspsa_result_viewer/route/practiscore_url.dart';
import 'package:uspsa_result_viewer/route/ratings.dart';
import 'configure_nonweb.dart' if (dart.library.html) 'configure_web.dart';
import 'package:fluro/fluro.dart' as fluro;

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
      return MatchSelectPage();
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
      await Future.delayed(Duration(milliseconds: 1));
    };
    MatchCache();
  }

  // sqfliteDatabaseFactory.setDatabasesPath(".");
  // var testDb = await $FloorProjectDatabase.databaseBuilder("test.sqlite").build();
  // testDb.database.execute("PRAGMA synchronous = OFF");
  // testDb.database.execute("PRAGMA journal_mode = WAL");
  //
  // print("Warming match/project cache");
  // await Future.wait([
  //   MatchCache().ready,
  //   RatingProjectManager().ready,
  // ]);
  // print("Match/project cache ready");
  //
  // var projectSettings = RatingProjectManager().loadProject("WPA And Friends 2020-2022")!;
  //
  // var matches = <PracticalMatch>[];
  // for(var matchUrl in projectSettings.matchUrls) {
  //   var m = await MatchCache().getMatch(matchUrl);
  //   if(m != null) matches.add(m);
  // }
  //
  // print("Calculating ratings");
  // var start = DateTime.now();
  // RatingHistory h = RatingHistory(matches: matches, settings: projectSettings.settings);
  // await h.processInitialMatches();
  //
  // var duration = DateTime.now().difference(start);
  // print("Done in ${duration.inMilliseconds}ms, starting DB dump");
  //
  // for(var rating in h.raterFor(h.matches.last, RaterGroup.open).uniqueShooters.sorted((a, b) => b.rating.compareTo(a.rating)).sublist(0, 5)) {
  //   print("$rating");
  // }
  //
  // start = DateTime.now();
  // var dbProject = await DbRatingProject.serialize(h, projectSettings, testDb);
  //
  // duration = DateTime.now().difference(start);
  // print("Dumped WPA ratings to DB in ${duration.inMilliseconds}ms");
  //
  // start = DateTime.now();
  // var deserialized = await dbProject.deserialize(testDb);
  // duration = DateTime.now().difference(start);
  //
  // print("Restored WPA ratings from DB in ${duration.inMilliseconds}ms");
  //
  // for(var rating in deserialized.raterFor(h.matches.last, RaterGroup.open).uniqueShooters.sorted((a, b) => b.rating.compareTo(a.rating)).sublist(0, 5)) {
  //   print("$rating");
  // }
  // var fileContents = await File("report.txt").readAsString();
  // var match = await processScoreFile(fileContents);
  // match.practiscoreIdShort = "12345";
  // match.practiscoreId = "long-uuid-id";
  //
  // await MatchCache().ready;
  // var start = DateTime.now();
  // for(var match in MatchCache().allMatches()) {
  //   var level = (match.level ?? MatchLevel.I);
  //   if(level != MatchLevel.I) {
  //     var innerStart = DateTime.now();
  //     await DbMatch.serialize(match, testDb);
  //     var duration = DateTime.now().difference(innerStart);
  //
  //     var rows = match.stages.length + match.shooters.length + match.stageScoreCount;
  //     print("Finished ${match.name} with $rows rows at ${((rows / duration.inMilliseconds) * 1000).round()}/sec");
  //   }
  // }
  //
  // var duration = DateTime.now().difference(start);
  //
  // print("Dumped L2s to DB in ${duration.inMilliseconds}ms");

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