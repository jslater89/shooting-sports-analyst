/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:convert';
import 'dart:io';

import 'package:hashlib/hashlib.dart';
import 'package:hashlib/random.dart';

String deriveMacOsKey() {
  var keyString = "${Platform.localHostname}-{Platform.environment['USER']}";
  var key = pbkdf2(utf8.encode(keyString), utf8.encode(_getSalt()));
  return key.hex();
}

String _getSalt() {
  var saltFile = File("db/efs.salt");
  if(!saltFile.existsSync()) {
    saltFile.createSync(recursive: true);
    var salt = _generateSalt();
    saltFile.writeAsStringSync(salt);
    return salt;
  }

  return saltFile.readAsStringSync();
}

String _generateSalt() {
  var bytes = HashlibRandom.secure().nextBytes(16);
  return base64Encode(bytes);
}
