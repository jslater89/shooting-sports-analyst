/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

// ignore: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' as foundation;
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shooting_sports_analyst/closed_sources/ssa_auth_client/flutter_machine_fingerprinter.dart';
import 'package:shooting_sports_analyst/config/config.dart';
import 'package:shooting_sports_analyst/config/encrypted_file_store/encrypted_file_store.dart';
import 'package:shooting_sports_analyst/config/encrypted_file_store/macos_key_deriver.dart';
import 'package:shooting_sports_analyst/config/secure_config.dart';
import 'package:shooting_sports_analyst/config/serialized_config.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/help/entries/all_helps.dart';
import 'package:shooting_sports_analyst/data/match_cache/registration_cache.dart';
import 'package:shooting_sports_analyst/data/ranking/rating_context.dart';
import 'package:shooting_sports_analyst/data/source/registered_sources.dart';
import 'package:shooting_sports_analyst/flutter_native_providers.dart';
import 'package:shooting_sports_analyst/html_or/html_or.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/route/local_upload.dart';
import 'package:shooting_sports_analyst/route/home_page.dart';
import 'package:shooting_sports_analyst/route/practiscore_url.dart';
import 'package:shooting_sports_analyst/route/ratings.dart';
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

class FlutterDebugProvider implements DebugModeProvider {
  bool get kDebugMode => foundation.kDebugMode;

  @override
  bool get kReleaseMode => foundation.kReleaseMode;
}

class FlutterConfigProvider implements ConfigProvider {
  FlutterConfigProvider(this._config);

  SerializedConfig _config;

  @override
  SerializedConfig get currentConfig => _config;

  @override
  void addListener(void Function(SerializedConfig config) listener) {
    ChangeNotifierConfigLoader().addListener(() {
      _config = ChangeNotifierConfigLoader().config;
      listener.call(_config);
    });
  }
}

class FlutterSecureStorageProvider implements SecureStorageProvider {

  static FlutterSecureStorageProvider? _instance;

  late FlutterSecureStorage _storage;
  late EncryptedFileStore _fileStore;

  factory FlutterSecureStorageProvider() {
    _instance ??= FlutterSecureStorageProvider._();
    return _instance!;
  }

  FlutterSecureStorageProvider._() {
    if(Platform.isMacOS) {
      _fileStore = EncryptedFileStore(key: deriveMacOsKey());
    }
    else {
      _storage = FlutterSecureStorage(
        mOptions: MacOsOptions(
          accessibility: KeychainAccessibility.first_unlock,
          synchronizable: true
        ),
      );
    }
  }

  @override
  Future<void> write(String key, String value) async {
    if(Platform.isMacOS) {
      await _fileStore.write(key, value);
    }
    else {
      await _storage.write(key: key, value: value);
    }
  }

  @override
  Future<String?> read(String key) async {
    if(Platform.isMacOS) {
      return await _fileStore.read(key);
    }
    else {
      return await _storage.read(key: key);
    }
  }

  @override
  Future<void> delete(String key) async {
    if(Platform.isMacOS) {
      await _fileStore.delete(key);
    }
    else {
      await _storage.delete(key: key);
    }
  }
}

void main() async {
  FlutterOrNative.debugModeProvider = FlutterDebugProvider();
  FlutterOrNative.machineFingerprintProvider = FlutterMachineFingerprinter();
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
        // _log.d("/ route params: $params");
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

    await ChangeNotifierConfigLoader().readyFuture;
    var initialConfig = ChangeNotifierConfigLoader().config;
    FlutterOrNative.configProvider = FlutterConfigProvider(initialConfig);

    var uiScaleFactor = ChangeNotifierConfigLoader().uiConfig.uiScaleFactor;

    await windowManager.ensureInitialized();
    var options = WindowOptions(
      minimumSize: Size(1280 * uiScaleFactor, 720 * uiScaleFactor),
      title: "Shooting Sports Analyst",
    );
    windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });

    SecureConfig.storageEngine = FlutterSecureStorageProvider();
    initLogger(initialConfig, FlutterOrNative.configProvider);

    await AnalystDatabase().ready;
    _log.i("Database ready");

    Hive.init((await getApplicationSupportDirectory()).absolute.path);

      await RegistrationCache().ready;
    _log.i("Registration cache ready");

    // oneoffDbAnalyses(AnalystDatabase());
    registerHelpTopics();

    // initialize match sources
    MatchSourceRegistry();

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
    ChangeNotifierConfigLoader().addListener(() async {
      await windowManager.ensureInitialized();
      var scaleFactor = ChangeNotifierConfigLoader().uiConfig.uiScaleFactor;
      await windowManager.setMinimumSize(Size(1280 * scaleFactor, 720 * scaleFactor));

      setState(() {
        // refresh theme mode
      });
    });
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
    var config = ChangeNotifierConfigLoader().uiConfig;

    final lightColorScheme = ColorScheme.fromSeed(
      seedColor: Colors.indigo,
      brightness: Brightness.light,
      secondary: Colors.indigo[300]!,
      surfaceContainerHigh: Color.fromARGB(255, 233, 231, 239),
    );
    final darkColorScheme = ColorScheme.fromSeed(
      seedColor: Colors.indigo,
      surface: Colors.grey[850]!,
      brightness: Brightness.dark,
      secondary: Colors.grey[800]!,
      onSecondary: Colors.grey[300]!,
      tertiary: Colors.indigo[300]!,
      surfaceContainerHigh: Color.fromARGB(255, 41, 41, 47),

    );

    final iconTheme = IconTheme.of(context).copyWith(applyTextScaling: true);
    final iconButtonTheme = IconButtonThemeData(
      style: IconButton.styleFrom(
        fixedSize: Size(36 * config.uiScaleFactor, 36 * config.uiScaleFactor),
        iconSize: 18 * config.uiScaleFactor,
        padding: EdgeInsets.zero,
        alignment: Alignment.center,
      ),
    );
    final bool material3 = true;

    final elevatedButtonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8 * config.uiScaleFactor)
    );
    final elevatedButtonPadding = EdgeInsets.symmetric(horizontal: 12 * config.uiScaleFactor, vertical: 6 * config.uiScaleFactor);
    final lightTheme = ThemeData(
      appBarTheme: AppBarTheme(
        color: lightColorScheme.secondary,
        iconTheme: iconTheme.copyWith(color: lightColorScheme.onSecondary),
        actionsIconTheme: iconTheme.copyWith(color: lightColorScheme.onSecondary),
        titleTextStyle: TextStyle(
          color: lightColorScheme.onSecondary,
          fontSize: 18 * config.uiScaleFactor,
        ),
        elevation: 3,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape: elevatedButtonShape,
          padding: elevatedButtonPadding
        ),
      ),
      dialogTheme: Theme.of(context).dialogTheme.copyWith(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6 * config.uiScaleFactor),
        ),
      ),
      cardTheme: Theme.of(context).cardTheme.copyWith(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4 * config.uiScaleFactor),
        ),
      ),
      tabBarTheme: Theme.of(context).tabBarTheme.copyWith(
        //labelColor:
      ),
      iconTheme: iconTheme,
      iconButtonTheme: iconButtonTheme,
      fontFamily: 'Ubuntu Sans',
      useMaterial3: material3,
      colorScheme: lightColorScheme,
      visualDensity: VisualDensity.adaptivePlatformDensity,
    );
    var darkTheme = ThemeData(
      appBarTheme: AppBarTheme(
        color: darkColorScheme.secondary,
        iconTheme: iconTheme.copyWith(color: darkColorScheme.onSecondary),
        actionsIconTheme: iconTheme.copyWith(color: darkColorScheme.onSecondary),
        titleTextStyle: TextStyle(
          color: darkColorScheme.onSecondary,
          fontSize: 18 * config.uiScaleFactor,
        ),
        elevation: 3,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape: elevatedButtonShape,
          padding: elevatedButtonPadding,
          foregroundColor: Colors.grey[300],
        )
      ),
      dialogTheme: lightTheme.dialogTheme,
      cardTheme: lightTheme.cardTheme,
      iconTheme: lightTheme.iconTheme.copyWith(
        color: Colors.grey[300],
      ),
      iconButtonTheme: iconButtonTheme,
      fontFamily: 'Ubuntu Sans',
      brightness: Brightness.dark,
      useMaterial3: material3,
      colorScheme: darkColorScheme,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      textTheme: lightTheme.textTheme.apply(
        bodyColor: Colors.grey[300],
        displayColor: Colors.grey[300],
        decorationColor: Colors.grey[300],
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: Colors.grey[800]!,
        contentTextStyle: TextStyle(
          color: Colors.grey[300],
        ),
        actionTextColor: Colors.indigo[300]!,
      ),
    );

    if(_prefs == null) {
      return MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(config.uiScaleFactor)),
        child: MaterialApp(
          title: 'Shooting Sports Analyst',
          theme: lightTheme,
          darkTheme: darkTheme,
          themeMode: config.themeMode,
          home: Container(),
        ),
      );
    }
    else {
      return MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(config.uiScaleFactor)),
        child: MultiProvider(
          providers: [
            Provider.value(value: _prefs!),
            ChangeNotifierProvider(create: (context) => RatingContext()),
          ],
          child: MaterialApp(
            title: 'Shooting Sports Analyst',
            theme: lightTheme,
            darkTheme: darkTheme,
            themeMode: config.themeMode,
            initialRoute: '/',
            onGenerateRoute: globals.router.generator,
          ),
        )
      );
    }
  }
}
