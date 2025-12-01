/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:io';
import 'dart:typed_data';

import 'package:shooting_sports_analyst/api/auth/openssh_keys.dart';

String _bytesToHex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

void main() {
  const fixtures = <String, String>{
    'old_private': '../old_rsa_pkcs1',
    'old_public': '../old_rsa_pkcs1.pub',
    'new_private': '../new_rsa_openssh',
    'new_public': '../new_rsa_openssh.pub',
    'ed_private': '../new_ed25519',
    'ed_public': '../new_ed25519.pub',
  };

  for (final name in fixtures.keys) {
    final path = fixtures[name]!;
    final text = File(path).readAsStringSync();
    if (name.endsWith('_public')) {
      final (type, data) = parsePublicKeyFile(text);
      print('--- $name ---');
      print('type=$type');
      if (data is OpenSSHRsaPublicKey) {
        print('modulus=${_bytesToHex(data.modulus)}');
        print('publicExponent=${_bytesToHex(data.publicExponent)}');
      } else if (data is Uint8List) {
        print(
          'hex=${_bytesToHex(data)}',
        );
      }
    } else {
      final (type, data) = parsePrivateKeyFile(text);
      print('--- $name ---');
      print('type=$type');
      if (data is OpenSSHRsaKeyPair) {
        print('modulus=${_bytesToHex(data.modulus)}');
        print('publicExponent=${_bytesToHex(data.publicExponent)}');
        print('privateExponent=${_bytesToHex(data.privateExponent)}');
        print('prime1=${_bytesToHex(data.prime1)}');
        print('prime2=${_bytesToHex(data.prime2)}');
        print('iqmp=${_bytesToHex(data.iqmp)}');
      }
      else if (data is OpenSSHEd25519KeyPair) {
        print(
          'pub=${_bytesToHex(data.publicKey)}',
        );
        print(
          'priv=${_bytesToHex(data.privateKey)}',
        );
      }
    }
  }
}
