import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';

/// File formats offered for match import (labels match product wording).
enum FileImportFormat {
  practiscoreReportTxt,
  practiscorePsc,
  practiscoreRegistrationZip,
  miff,
  riff,
  autoDetect;

  String get label {
    switch (this) {
      case FileImportFormat.practiscoreReportTxt:
        return "Practiscore report.txt";
      case FileImportFormat.practiscorePsc:
        return "Practiscore .psc";
      case FileImportFormat.practiscoreRegistrationZip:
        return "Practiscore registration page source zip";
      case FileImportFormat.miff:
        return "MIFF";
      case FileImportFormat.riff:
        return "RIFF";
      case FileImportFormat.autoDetect:
        return "Auto-detect";
    }
  }
}

const _gzipHeader = [0x1f, 0x8b];
const _zipHeader = [0x50, 0x4b, 0x03, 0x04];
const _psTxtHeader = [
  0x24, // $
  0x50, // P
  0x52, // R
  0x41, // A
  0x43, // C
  0x54, // T
  0x49, // I
  0x53, // S
  0x43, // C
  0x4F, // O
  0x52, // R
  0x45, // E
];

final _miffRegex = RegExp(r'"format":\s*"miff"');
final _riffRegex = RegExp(r'"format":\s*"riff"');

Future<FileImportFormat?> detectFormat(File file) async {
  List<int> bytes = await file.readAsBytes();
  final header = bytes.sublist(0, 1024);

  if(_arrayStartsWith(header, _gzipHeader)) {
    return _processGzip(bytes);
  }
  else if(_arrayStartsWith(header, _zipHeader)) {
    return _processZip(bytes);
  }
  else {
    return _processPlainText(bytes);
  }
}

bool _arrayStartsWith(List<int> array, List<int> prefix) {
  if(array.length < prefix.length) {
    return false;
  }
  for(var i = 0; i < prefix.length; i++) {
    if(array[i] != prefix[i]) {
      return false;
    }
  }
  return true;
}

/// A gzip-compressed file is either a MIFF or RIFF file.
Future<FileImportFormat?> _processGzip(List<int> bytes) async {
  var unzipped = gzip.decode(bytes);
  return _processPlainText(unzipped);
}

/// A zip file is either a Practiscore registration page source zip or a
/// psc/Competitor zip file.
Future<FileImportFormat?> _processZip(List<int> bytes) async {
  var zip = ZipDecoder().decodeBytes(bytes);
  for(var entry in zip) {
    if(entry.name == "squadding.html") {
      return FileImportFormat.practiscoreRegistrationZip;
    }
    else if(entry.name == "match_def.json") {
      return FileImportFormat.practiscorePsc;
    }
  }
  return null;
}

/// A plain text file is a Practiscore report.txt file or an uncompressed
/// miff/riff file.
Future<FileImportFormat?> _processPlainText(List<int> bytes) async {
  if(_arrayStartsWith(bytes, _psTxtHeader)) {
    return FileImportFormat.practiscoreReportTxt;
  }
  final text = utf8.decode(bytes);
  final header = text.substring(0, 1024);
  if(_miffRegex.hasMatch(header)) {
    return FileImportFormat.miff;
  }
  else if(_riffRegex.hasMatch(header)) {
    return FileImportFormat.riff;
  }
  return null;
}