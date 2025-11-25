import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shooting_sports_analyst/api/auth/openssh_keys.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final fixtureFile = File('test/api/auth/fixtures/key_data.json');
  final Map<String, dynamic> fixtures = jsonDecode(
    fixtureFile.readAsStringSync(),
  );

  group('RSA fixtures', () {
    test('old RSA private key parses cleanly', () {
      final fixture = fixtures['old_rsa']['private'] as Map<String, dynamic>;
      final parsed = parsePrivateKeyFile(
        File('test/api/auth/fixtures/old_rsa_pkcs1').readAsStringSync(),
      );
      expect(parsed.$1, 'ssh-rsa');
      final data = parsed.$2 as OpenSSHRsaKeyPair;
      _expectRsaPair(data, fixture);
    });

    test('old RSA public key matches expected', () {
      final fixture = fixtures['old_rsa']['public'] as Map<String, dynamic>;
      final parsed = parsePublicKeyFile(
        File('test/api/auth/fixtures/old_rsa_pkcs1.pub').readAsStringSync(),
      );
      expect(parsed.$1, 'ssh-rsa');
      final data = parsed.$2 as OpenSSHRsaPublicKey;
      _expectRsaPublic(data, fixture);
    });

    test('new RSA private key parses cleanly', () {
      final fixture = fixtures['new_rsa']['private'] as Map<String, dynamic>;
      final parsed = parsePrivateKeyFile(
        File('test/api/auth/fixtures/new_rsa_openssh').readAsStringSync(),
      );
      expect(parsed.$1, 'ssh-rsa');
      final data = parsed.$2 as OpenSSHRsaKeyPair;
      _expectRsaPair(data, fixture);
    });

    test('new RSA public key matches expected', () {
      final fixture = fixtures['new_rsa']['public'] as Map<String, dynamic>;
      final parsed = parsePublicKeyFile(
        File('test/api/auth/fixtures/new_rsa_openssh.pub').readAsStringSync(),
      );
      expect(parsed.$1, 'ssh-rsa');
      final data = parsed.$2 as OpenSSHRsaPublicKey;
      _expectRsaPublic(data, fixture);
    });
  });

  group('ed25519 fixtures', () {
    test('Ed25519 private key returns raw bytes', () {
      final fixture = fixtures['ed25519']['private'] as Map<String, dynamic>;
      final parsed = parsePrivateKeyFile(
        File('test/api/auth/fixtures/new_ed25519').readAsStringSync(),
      );
      expect(parsed.$1, 'ssh-ed25519');
      final data = parsed.$2 as OpenSSHEd25519KeyPair;
      expect(_bytesToHex(data.publicKey), fixture['public']);
      expect(_bytesToHex(data.privateKey), fixture['private']);
    });

    test('Ed25519 public key returns raw bytes', () {
      final expected = fixtures['ed25519']['public'] as String;
      final parsed = parsePublicKeyFile(
        File('test/api/auth/fixtures/new_ed25519.pub').readAsStringSync(),
      );
      expect(parsed.$1, 'ssh-ed25519');
      expect(parsed.$2, isA<Uint8List>());
      expect(_bytesToHex(parsed.$2 as Uint8List), expected);
    });
  });
}

void _expectRsaPair(OpenSSHRsaKeyPair actual, Map<String, dynamic> expected) {
  expect(actual.modulus, _hexBigInt(expected['modulus'] as String));
  expect(
    actual.publicExponent,
    _hexBigInt(expected['publicExponent'] as String),
  );
  expect(
    actual.privateExponent,
    _hexBigInt(expected['privateExponent'] as String),
  );
  expect(actual.prime1, _hexBigInt(expected['prime1'] as String));
  expect(actual.prime2, _hexBigInt(expected['prime2'] as String));
  expect(actual.iqmp, _hexBigInt(expected['iqmp'] as String));
}

void _expectRsaPublic(
  OpenSSHRsaPublicKey actual,
  Map<String, dynamic> expected,
) {
  expect(actual.modulus, _hexBigInt(expected['modulus'] as String));
  expect(
    actual.publicExponent,
    _hexBigInt(expected['publicExponent'] as String),
  );
}

BigInt _hexBigInt(String hex) => BigInt.parse(hex, radix: 16);

String _bytesToHex(Uint8List bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
