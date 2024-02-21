/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

const _RELEASE_FILTER_LEVEL = Level.debug;

SSALogger _log = SSALogger.consoleOnly("LoggerInternal");

class _SSALogFilter extends LogFilter {
  @override
  bool shouldLog(LogEvent event) {
    if(kReleaseMode) {
      if(event.level >= _RELEASE_FILTER_LEVEL) {
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

class _SSALogOutput extends LogOutput {
  final bool console;
  final bool file;

  late Future<bool> launchFuture;

  static const _LOG_DIR = "./logs/";
  static const _FILENAME = "./logs/analyst.log";

  /// Keep main file and two more.
  static const _FILE_LIMIT = 3;

  static const _MAX_FILE_SIZE = 1024 * 1024 * 5;
  static const _MIN_FILE_DELAY = 60;

  static DateTime _lastFileRotateCheck = DateTime.now();

  List<File> _outputFiles = [];

  _SSALogOutput({this.console = true, this.file = false}) {
    if(file) launchFuture = _setupFiles();
    else launchFuture = Future.value(true);
  }

  Future<bool> _setupFiles() async {
    if(_outputFiles.isNotEmpty) {
      return true;
    }

    var dir = Directory(_LOG_DIR);
    if(!dir.existsSync()) {
      _log.v("Creating directory $_LOG_DIR");
      await dir.create();
    }

    _reloadFilesArray();

    return true;
  }

  void _reloadFilesArray() {
    List<File> files = [];
    for(int i = 0; i < _FILE_LIMIT; i++) {
      files.add(_fileForIndex(i));
    }

    _outputFiles = files;
  }
  
  List<String> _buffer = [];

  @override
  void output(OutputEvent event) async {
    await launchFuture;

    if(this.console) event.lines.forEach((element) { print(element); });
    if(this.file) _doFileOutput(event.lines.join("\n"));
  }

  bool _pumping = false;
  void _pumpOutput() async {
    if(!_pumping) {
      _pumping = true;

      var f = _outputFiles.first;

      while(_buffer.isNotEmpty) {
        var output = _buffer.removeAt(0);
        String suffix = "";
        if(!output.endsWith("\n")) suffix = "\n";

        await f.writeAsString(output + suffix, mode: FileMode.append);
      }

      if(DateTime.now().difference(_lastFileRotateCheck).inSeconds > _MIN_FILE_DELAY) {
        var stat = await f.stat();
        if(stat.size > _MAX_FILE_SIZE) {
          _rotateFiles();
        }
      }

      _pumping = false;
    }
  }

  Future<void> _doFileOutput(String output) async {
    _buffer.add(output);

    _pumpOutput();
  }

  void _rotateFiles() async {
    _outputFiles.last.deleteSync();

    for(int i = 0; i < _FILE_LIMIT - 1; i++) {
      var f = _fileForIndex(i);
      f.rename(_filenameForIndex(i + 1));
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

class SSALogger extends LogPrinter {
  static late _SSALogOutput _output;
  static Level _minLevel = kDebugMode ? Level.trace : Level.info;
  Logger? _logger;

  final String tag;
  SSALogger(this.tag) {
    if(_logger == null) {
      _output = _SSALogOutput(console: true, file: true);
      _logger = new Logger(
        printer: this,
        filter: _SSALogFilter(),
        output: _output,
      );
    }
  }
  SSALogger.consoleOnly(this.tag) {
    if(_logger == null) {
      _output = _SSALogOutput(console: true, file: false);
      _logger = new Logger(
        printer: this,
        filter: _SSALogFilter(),
        output: _output,
      );
    }
  }

  Future<bool> ready() {
    return _output.launchFuture;
  }

  /// Logs in Verbose mode, and never logs in release mode no matter
  /// what the filter is set to.
  void vv(dynamic message, {dynamic error, StackTrace? stackTrace}) {
    if(kReleaseMode) return;
    _logger!.t("VV:$message", error: error, stackTrace: stackTrace);
  }
  void v(dynamic message, {dynamic error, StackTrace? stackTrace}) => _logger!.t(message, error: error, stackTrace: stackTrace);
  void d(dynamic message, {dynamic error, StackTrace? stackTrace}) => _logger!.d(message, error: error, stackTrace: stackTrace);
  void i(dynamic message, {dynamic error, StackTrace? stackTrace}) => _logger!.i(message, error: error, stackTrace: stackTrace);
  void w(dynamic message, {dynamic error, StackTrace? stackTrace}) => _logger!.w(message, error: error, stackTrace: stackTrace);
  void e(dynamic message, {dynamic error, StackTrace? stackTrace}) => _logger!.e(message, error: error, stackTrace: stackTrace);

  @override
  List<String> log(LogEvent event) {
    if(event.level.index < _minLevel.index || event.level == Level.off) {
      return [];
    }

    String info = "[${_translateLevel(event.level)}] $tag ${DateTime.now().toString()} ::: ";
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