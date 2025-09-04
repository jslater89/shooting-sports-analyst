
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

String deriveMacOsKey() {
  var keyString = "${Platform.localHostname}-{Platform.environment['USER']}";
  var key = sha256.convert(utf8.encode(keyString)).toString();
  return key;
}
