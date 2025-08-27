/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:mutex/mutex.dart';
import 'package:shooting_sports_analyst/config/config.dart';
import 'package:stack_trace/stack_trace.dart';

SSALogger _log = SSALogger.consoleOnly("LoggerInternal");

// We will log at trace level until config is loaded, at which
// point either the config file or the default in config.dart
// takes effect.
Level _minLevel = Level.trace;

void initLogger() {
  var logDir = Directory(_SSAFileOutput._LOG_DIR);
  if(!logDir.existsSync()) {
    logDir.createSync(recursive: true);
  }

  ConfigLoader().addListener(() {
    _minLevel = ConfigLoader().config.logLevel;
  });
}

class _SSALogFilter extends LogFilter {
  @override
  bool shouldLog(LogEvent event) {
    if(kReleaseMode) {
      if(event.level >= _minLevel) {
        return true;
      }
      else {
        return false;
      }
    }
    return true;
  }
}

extension _LevelComparison on Level {
  bool operator >(Level other) {
    return Level.values.indexOf(this) > Level.values.indexOf(other);
  }

  bool operator >=(Level other) {
    return Level.values.indexOf(this) >= Level.values.indexOf(other);
  }

  bool operator <(Level other) {
    return Level.values.indexOf(this) < Level.values.indexOf(other);
  }

  bool operator <=(Level other) {
    return Level.values.indexOf(this) <= Level.values.indexOf(other);
  }
}

class _SSAFileOutput {
  static _SSAFileOutput? _instance;
  factory _SSAFileOutput() {
    _instance ??= _SSAFileOutput._();
    return _instance!;
  }

  _SSAFileOutput._() {
    launchFuture = _launchCompleter.future;
    _setupFiles();
  }

  late Future<bool> launchFuture;
  Completer<bool> _launchCompleter = Completer();

  static const _LOG_DIR = "./logs/";
  static const _FILENAME = "./logs/analyst.log";

  /// Keep main file and 24 more.
  static const _FILE_LIMIT = 25;

  static const _MAX_FILE_SIZE = 1024 * 1024 * 5;
  static const _MIN_FILE_DELAY = 60;

  DateTime _lastFileRotateCheck = DateTime.now();
  List<String> _buffer = [];
  List<File> _outputFiles = [];
  Mutex _fileLock = Mutex();

  /// This will be called once when the file output instance
  /// is created, so it doesn't need locking.
  Future<void> _setupFiles() async {
    if(_outputFiles.isNotEmpty) {
      return;
    }

    var dir = Directory(_LOG_DIR);
    if(!dir.existsSync()) {
      await dir.create();
    }

    _reloadFilesArray();

    // At app start, rotate files, so we start
    // a new log file per app run.
    _rotateFiles();

    _launchCompleter.complete(true);
    return;
  }

  void _reloadFilesArray() {
    List<File> files = [];
    for(int i = 0; i < _FILE_LIMIT; i++) {
      files.add(_fileForIndex(i));
    }

    _outputFiles = files;
  }

  /// Write to logs.
  Future<void> _pumpOutput() async {
    if(!_fileLock.isLocked) {
      await _fileLock.acquire();

      var f = _outputFiles.first;
      var fo = f.openSync(mode: FileMode.append);

      while(_buffer.isNotEmpty) {
        var output = _buffer.removeAt(0);
        String suffix = "";
        if(!output.endsWith("\n")) suffix = "\n";

        await fo.writeString(output + suffix);
      }

      fo.closeSync();

      if(DateTime.now().difference(_lastFileRotateCheck).inSeconds > _MIN_FILE_DELAY) {
        var stat = await f.stat();
        if(stat.size > _MAX_FILE_SIZE) {
          _rotateFiles();
        }
      }

      _fileLock.release();
    }
  }

  Future<void> write(String output) async {
    _buffer.add(output);

    _pumpOutput();
  }

  void _rotateFiles() {
    // Delete the oldest file
    if(_outputFiles.last.existsSync()) {
      _outputFiles.last.deleteSync();
    }

    // Working from old to new, rename each file to the filename one older.
    for(int i = _FILE_LIMIT - 2; i >= 0; i--) {
      var f = _fileForIndex(i);
      if(f.existsSync()) {
        f.renameSync(_filenameForIndex(i + 1));
      }
    }

    _reloadFilesArray();
  }

  String _filenameForIndex(int i) {
    if(i == 0) return _FILENAME;
    else return "$_FILENAME.$i";
  }

  File _fileForIndex(int i) {
    File f;
    if(i == 0) f = File(_filenameForIndex(i));
    else f = File(_filenameForIndex(i));
    return f;
  }

}

class _SSALogOutput extends LogOutput {
  final bool console;
  final bool file;

  _SSAFileOutput fileOutput = _SSAFileOutput();

  late Future<bool> launchFuture;

  _SSALogOutput({this.console = true, this.file = false}) {
    if(file) launchFuture = fileOutput.launchFuture;
    else launchFuture = Future.value(true);
  }

  @override
  void output(OutputEvent event) async {
    await launchFuture;

    if(this.console) event.lines.forEach((element) { print(element); });
    if(this.file) fileOutput.write(event.lines.join("\n"));
  }
}

class SSALogger extends LogPrinter {
  static const _callsiteLevel = kDebugMode ? Level.debug : Level.warning;

  late _SSALogOutput _output;
  late Logger _logger;

  final String tag;
  SSALogger(this.tag) {
    _init(true);
  }
  SSALogger.consoleOnly(this.tag) {
    _init(false);
  }

  Future<void> get ready => _readyCompleter.future;
  Completer<void> _readyCompleter = Completer();

  Future<void> _init(bool file) async {
    // This needs to be able to load independently of other
    // components,
    _minLevel = Level.trace;

    _output = _SSALogOutput(console: true, file: true);
    _logger = new Logger(
      printer: this,
      filter: _SSALogFilter(),
      output: _output,
    );
  }

  Future<void> canLog() async {
    await Future.wait([ready, _output.launchFuture]);
  }

  /// Logs in Verbose mode, and never logs in release mode no matter
  /// what the filter is set to.
  void vv(dynamic message, {dynamic error, StackTrace? stackTrace}) {
    if(kReleaseMode) return;
    _logger.t("VV:$message", error: error, stackTrace: stackTrace);
  }
  void v(dynamic message, {dynamic error, StackTrace? stackTrace}) => _logger.t(message, error: error, stackTrace: stackTrace);
  void d(dynamic message, {dynamic error, StackTrace? stackTrace}) => _logger.d(message, error: error, stackTrace: stackTrace);
  void i(dynamic message, {dynamic error, StackTrace? stackTrace}) => _logger.i(message, error: error, stackTrace: stackTrace);
  void w(dynamic message, {dynamic error, StackTrace? stackTrace}) => _logger.w(message, error: error, stackTrace: stackTrace);
  void e(dynamic message, {dynamic error, StackTrace? stackTrace}) => _logger.e(message, error: error, stackTrace: stackTrace);

  @override
  List<String> log(LogEvent event) {
    if(event.level.index < _minLevel.index || event.level == Level.off) {
      return [];
    }

    String callsite = "";
    if(event.level >= _callsiteLevel) {
      var stacktrace = Trace.current();
      if(stacktrace.frames.length >= 5) {
        var frame = stacktrace.frames[4];
        callsite = "<${frame.library.replaceFirst("package:shooting_sports_analyst/", "")} ${frame.line ?? "?"}:${frame.column ?? "?"}> ";
      }
    }

    String info = "[${_translateLevel(event.level)}] $tag ${DateTime.now().toString()} ::: $callsite";
    List<String> lines = ["$info ${event.message}"];

    if(event.error != null) {
      lines.add("(${event.error.runtimeType}) ${event.error}");
    }

    List<String>? stacktraceLines = event.stackTrace?.toString().split("\n");
    if(stacktraceLines != null) {
      lines.addAll(stacktraceLines);
    }

    return lines;
  }

  static String _translateLevel(Level l) {
    switch(l) {
      case Level.trace || Level.verbose:
        return "VERBOSE";
      case Level.debug:
        return " DEBUG ";
      case Level.info:
        return " INFO  ";
      case Level.warning:
        return " WARN  ";
      case Level.error:
        return " ERROR ";
      case Level.fatal || Level.wtf:
        return "  WTF  ";
      case Level.off || Level.nothing:
        return "unused";
      default:
        return "impossible";
    }
  }
}
