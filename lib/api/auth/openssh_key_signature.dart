/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:shooting_sports_analyst/api/auth/openssh_keys.dart';
import 'package:shooting_sports_analyst/logger.dart';

// ignore: unused_element
final _log = SSALogger("OpenSSHKeySignature");

Future<Signature> signMessage(String message, String privateKeyContents) async {
  var (typeString, privateKeyObject) = parsePrivateKeyFile(privateKeyContents);
  SignatureAlgorithm? signatureAlgorithm;
  KeyPair? privateKey;
  if(typeString == ed25519KeyType) {
    var keyObject = privateKeyObject as OpenSSHEd25519KeyPair;
    signatureAlgorithm = Ed25519();
    privateKey = SimpleKeyPairData(
      keyObject.privateKey,
      publicKey: SimplePublicKey(keyObject.publicKey, type: KeyPairType.ed25519),
      type: KeyPairType.ed25519,
    );
  }
  else if(typeString == rsaKeyType) {
    var keyObject = privateKeyObject as OpenSSHRsaKeyPair;
    signatureAlgorithm = RsaPss(Sha256());
    privateKey = RsaKeyPairData(
      n: keyObject.modulus,
      e: keyObject.publicExponent,
      d: keyObject.privateExponent,
      p: keyObject.prime1,
      q: keyObject.prime2,
    );
  }
  if(signatureAlgorithm == null || privateKey == null) {
    throw Exception('Invalid private key');
  }
  var signature = await signatureAlgorithm.sign(
    utf8.encode(message),
    keyPair: privateKey,
  );

  // _log.v("Signed message: $message (as utf8)");
  // _log.v("SignatureB64: ${base64.encode(signature.bytes)}");

  return signature;
}

Future<bool> verifySignature(String message, String signatureB64, String publicKeyContents) async {
  var (typeString, publicKeyObject) = parsePublicKeyFile(publicKeyContents);
  SignatureAlgorithm? signatureAlgorithm;
  PublicKey? publicKey;
  if(typeString == ed25519KeyType) {
    var keyObject = publicKeyObject as OpenSSHEd25519PublicKey;
    var cryptoPublicKey = SimplePublicKey(keyObject.publicKey, type: KeyPairType.ed25519);
    signatureAlgorithm = Ed25519();
    publicKey = cryptoPublicKey;
  }
  else if(typeString == rsaKeyType) {
    var keyObject = publicKeyObject as OpenSSHRsaPublicKey;
    var cryptoPublicKey = RsaPublicKey(e: keyObject.publicExponent, n: keyObject.modulus);
    signatureAlgorithm = RsaPss(Sha256());
    publicKey = cryptoPublicKey;
  }
  if(signatureAlgorithm == null || publicKey == null) {
    return false;
  }

  var signedMessageBytes = utf8.encode(message);
  var signatureBytes = base64.decode(signatureB64);

  // _log.v("Verifying signature for message: $message (as utf8)");
  // _log.v("SignatureB64: $signatureB64");
  return await signatureAlgorithm.verify(
    signedMessageBytes,
    signature: Signature(signatureBytes, publicKey: publicKey),
  );
}