/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/main.dart';

class SecureConfig {
  static const _psUsernameKey = "ps_username";
  static const _psPasswordKey = "ps_password";

  static final _storage = FlutterSecureStorageProvider();

  static Future<void> setPsUsername(String username) async {
    await _storage.write(_psUsernameKey, username);
  }

  static Future<void> setPsPassword(String password) async {
    await _storage.write(_psPasswordKey, password);
  }

  static Future<(String?, String?)> getPsCredentials() async {
    var username = await _storage.read(_psUsernameKey);
    var password = await _storage.read(_psPasswordKey);
    return (username, password);
  }

  static Future<void> clearPsCredentials() async {
    await _storage.delete(_psUsernameKey);
    await _storage.delete(_psPasswordKey);
  }
}

abstract class SecureStorageProvider {
  Future<void> write(String key, String value);
  Future<String?> read(String key);
  Future<void> delete(String key);
}
