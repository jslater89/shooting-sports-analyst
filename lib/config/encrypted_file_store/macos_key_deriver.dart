
import 'dart:convert';
import 'dart:io';

import 'package:hashlib/hashlib.dart';
import 'package:hashlib/random.dart';
import 'package:uuid/uuid.dart';

String deriveMacOsKey() {
  var keyString = "${Platform.localHostname}-${Platform.environment['USER']}-${_getUuid()}";
  var key = argon2id(utf8.encode(keyString), utf8.encode(_getSalt()), hashLength: 32, security: Argon2Security.good);
  return key.hex();
}

String _getUuid() {
  var uuidFile = File("db/efs.uuid");
  if(!uuidFile.existsSync()) {
    uuidFile.createSync(recursive: true);
    var uuid = Uuid().v4();
    uuidFile.writeAsStringSync(uuid);
    return uuid;
  }

  return uuidFile.readAsStringSync();
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
