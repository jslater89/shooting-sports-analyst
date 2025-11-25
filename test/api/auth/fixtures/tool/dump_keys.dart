import 'dart:io';
import 'dart:typed_data';

import 'package:shooting_sports_analyst/api/auth/openssh_keys.dart';

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
        print('modulus=${data.modulus.toRadixString(16)}');
        print('publicExponent=${data.publicExponent.toRadixString(16)}');
      } else if (data is Uint8List) {
        print(
          'hex=${data.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}',
        );
      }
    } else {
      final (type, data) = parsePrivateKeyFile(text);
      print('--- $name ---');
      print('type=$type');
      if (data is OpenSSHRsaKeyPair) {
        print('modulus=${data.modulus.toRadixString(16)}');
        print('publicExponent=${data.publicExponent.toRadixString(16)}');
        print('privateExponent=${data.privateExponent.toRadixString(16)}');
        print('prime1=${data.prime1.toRadixString(16)}');
        print('prime2=${data.prime2.toRadixString(16)}');
        print('iqmp=${data.iqmp.toRadixString(16)}');
      } else if (data is OpenSSHEd25519KeyPair) {
        print(
          'pub=${data.publicKey.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}',
        );
        print(
          'priv=${data.privateKey.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}',
        );
      }
    }
  }
}
