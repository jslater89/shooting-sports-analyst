/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureConfig {
  static const _psUsernameKey = "ps_username";
  static const _psPasswordKey = "ps_password";

  static Future<void> setPsUsername(String username) async {
    await FlutterSecureStorage().write(key: _psUsernameKey, value: username);
  }

  static Future<void> setPsPassword(String password) async {
    await FlutterSecureStorage().write(key: _psPasswordKey, value: password);
  }

  static Future<(String?, String?)> getPsCredentials() async {
    var username = await FlutterSecureStorage().read(key: _psUsernameKey);
    var password = await FlutterSecureStorage().read(key: _psPasswordKey);
    return (username, password);
  }

  static Future<void> clearPsCredentials() async {
    await FlutterSecureStorage().delete(key: _psUsernameKey);
    await FlutterSecureStorage().delete(key: _psPasswordKey);
  }
}

abstract class SecureStorageProvider {
  Future<void> write(String key, String value);
  Future<String?> read(String key);
  Future<void> delete(String key);
}
