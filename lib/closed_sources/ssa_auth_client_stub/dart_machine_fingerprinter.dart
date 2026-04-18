import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:shooting_sports_analyst/flutter_native_providers.dart';
import 'package:shooting_sports_analyst/util.dart';

class DartOnlyMachineFingerprinter implements MachineFingerprintProvider {
  String fpPath = ".fingerprint";
  @override
  Future<String> getMachineFingerprint() {
    var fpFile = File(fpPath);
    if(!fpFile.existsSync()) {
      fpFile.createSync(recursive: true);
      var fp = _generateFingerprint();
      fpFile.writeAsStringSync(fp);
    }
    return fpFile.readAsString();
  }

  String _generateFingerprint() {
    var bytes = Random.secure().nextBytes(16);
    var fp = base64Encode(bytes);
    return fp;
  }
}
